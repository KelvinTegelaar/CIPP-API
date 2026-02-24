using namespace System.Net

function Invoke-ExecCreateAppTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -headers $Request.headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Body.TenantFilter
        $AppId = $Request.Body.AppId
        $DisplayName = $Request.Body.DisplayName
        $Type = $Request.Body.Type # 'servicePrincipal' or 'application'
        $Overwrite = $Request.Body.Overwrite -eq $true

        if ([string]::IsNullOrWhiteSpace($AppId)) {
            throw 'AppId is required'
        }

        if ([string]::IsNullOrWhiteSpace($DisplayName)) {
            throw 'DisplayName is required'
        }

        # Build initial bulk request to get app registration and all service principals
        # The SP we need will be in the splist, so we don't need a separate call
        $InitialBulkRequests = @(
            [PSCustomObject]@{
                id     = 'app'
                method = 'GET'
                url    = "/applications(appId='$AppId')?`$select=id,appId,displayName,requiredResourceAccess"
            }
            [PSCustomObject]@{
                id     = 'splist'
                method = 'GET'
                url    = '/servicePrincipals?$top=999&$select=id,appId,displayName'
            }
        )

        Write-Information "Retrieving app details for AppId: $AppId in tenant: $TenantFilter"
        $InitialResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests $InitialBulkRequests -NoAuthCheck $true -AsApp $true

        $AppResult = $InitialResults | Where-Object { $_.id -eq 'app' } | Select-Object -First 1
        $TenantInfo = ($InitialResults | Where-Object { $_.id -eq 'splist' }).body.value

        # Find the specific service principal in the list
        $SPResult = $TenantInfo | Where-Object { $_.appId -eq $AppId } | Select-Object -First 1

        # Get the app details based on type
        if ($Type -eq 'servicePrincipal') {
            if (-not $SPResult) {
                throw "Service principal not found for AppId: $AppId"
            }

            $App = $SPResult

            # Check if we got the app registration and it has permissions
            if ($AppResult.status -eq 200 -and $AppResult.body.requiredResourceAccess -and $AppResult.body.requiredResourceAccess.Count -gt 0) {
                Write-LogMessage -headers $Request.headers -API $APINAME -message "Retrieved requiredResourceAccess from app registration for $AppId" -Sev 'Info'
                $Permissions = $AppResult.body.requiredResourceAccess
            } else {
                # App registration not accessible or no permissions configured
                # Build permissions from oauth2PermissionGrants and appRoleAssignments
                Write-LogMessage -headers $Request.headers -API $APINAME -message "Could not retrieve app registration for $AppId - extracting from service principal grants and role assignments" -Sev 'Info'

                # Bulk request to get grants and assignments
                $GrantsBulkRequests = @(
                    [PSCustomObject]@{
                        id     = 'grants'
                        method = 'GET'
                        url    = "/servicePrincipals(appId='$AppId')/oauth2PermissionGrants"
                    }
                    [PSCustomObject]@{
                        id     = 'assignments'
                        method = 'GET'
                        url    = "/servicePrincipals(appId='$AppId')/appRoleAssignments"
                    }
                )

                $GrantsResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests $GrantsBulkRequests -NoAuthCheck $true -AsApp $true

                $DelegatePermissionGrants = ($GrantsResults | Where-Object { $_.id -eq 'grants' }).body.value
                $AppRoleAssignments = ($GrantsResults | Where-Object { $_.id -eq 'assignments' }).body.value

                $DelegateResourceAccess = $DelegatePermissionGrants | Group-Object -Property resourceId | ForEach-Object {
                    $resourceAccessList = [System.Collections.Generic.List[object]]::new()
                    foreach ($Grant in $_.Group) {
                        if (-not [string]::IsNullOrWhiteSpace($Grant.scope)) {
                            $scopeNames = $Grant.scope -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                            foreach ($scopeName in $scopeNames) {
                                $resourceAccessList.Add([pscustomobject]@{
                                        id   = $scopeName
                                        type = 'Scope'
                                    })
                            }
                        }
                    }
                    [pscustomobject]@{
                        resourceAppId  = ($TenantInfo | Where-Object -Property id -EQ $_.Name).appId
                        resourceAccess = @($resourceAccessList)
                    }
                }

                $ApplicationResourceAccess = $AppRoleAssignments | Group-Object -Property ResourceId | ForEach-Object {
                    [pscustomobject]@{
                        resourceAppId  = ($TenantInfo | Where-Object -Property id -EQ $_.Name).appId
                        resourceAccess = @($_.Group | ForEach-Object {
                                [pscustomobject]@{
                                    id   = $_.appRoleId
                                    type = 'Role'
                                }
                            })
                    }
                }

                # Combine both delegated and application permissions
                $Permissions = @($DelegateResourceAccess) + @($ApplicationResourceAccess) | Where-Object { $_ -ne $null }

                if ($Permissions.Count -eq 0) {
                    Write-LogMessage -headers $Request.headers -API $APINAME -message "No permissions found for $AppId via any method" -sev 'Warn'
                } else {
                    Write-LogMessage -headers $Request.headers -API $APINAME -message "Extracted $($Permissions.Count) resource permission(s) from service principal grants" -Sev 'Info'
                }
            }
        } else {
            # For app registrations (applications)
            if ($AppResult.status -ne 200 -or -not $AppResult.body) {
                throw "App registration not found for AppId: $AppId"
            }

            $App = $AppResult.body

            $Tenant = Get-Tenants -TenantFilter $TenantFilter
            if ($Tenant.customerId -ne $env:TenantID) {
                $ExistingApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$DisplayName'" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true

                if ($ExistingApp) {
                    Write-Information "App Registration $AppId already exists in partner tenant"
                    $AppId = $ExistingApp.appId
                    $App = $ExistingApp
                    Write-LogMessage -headers $Request.headers -API $APINAME -message "App Registration $($AppDetails.displayName) already exists in partner tenant" -Sev 'Info'
                } else {
                    Write-Information "Copying App Registration $AppId from customer tenant $TenantFilter to partner tenant"
                    $PropertiesToRemove = @(
                        'appId'
                        'id'
                        'createdDateTime'
                        'deletedDateTime'
                        'publisherDomain'
                        'servicePrincipalLockConfiguration'
                        'identifierUris'
                        'applicationIdUris'
                        'keyCredentials'
                        'passwordCredentials'
                        'isDisabled'
                    )
                    $AppCopyBody = $App | Select-Object -Property * -ExcludeProperty $PropertiesToRemove
                    # Remove any null properties
                    $NullProperties = [System.Collections.Generic.List[string]]::new()
                    foreach ($Property in $AppCopyBody.PSObject.Properties.Name) {
                        if ($null -eq $AppCopyBody.$Property -or $AppCopyBody.$Property -eq '' -or !$AppCopyBody.$Property) {
                            Write-Information "Removing null property $Property from app copy body"
                            $NullProperties.Add($Property)
                        }
                    }
                    $AppCopyBody = $AppCopyBody | Select-Object -Property * -ExcludeProperty $NullProperties
                    if ($AppCopyBody.signInAudience -eq 'AzureADMyOrg') {
                        # Enterprise apps cannot be copied to another tenant
                        $AppCopyBody.signInAudience = 'AzureADMultipleOrgs'
                    }
                    if ($AppCopyBody.web -and $AppCopyBody.web.redirectUris) {
                        # Remove redirect URI settings if property exists
                        $AppCopyBody.web.PSObject.Properties.Remove('redirectUriSettings')
                    }
                    if ($AppCopyBody.api.oauth2PermissionScopes) {
                        $AppCopyBody.api.oauth2PermissionScopes = @(foreach ($Scope in $AppCopyBody.api.oauth2PermissionScopes) {
                                $Scope | Select-Object * -ExcludeProperty 'isPrivate'
                            })
                    }
                    if ($AppCopyBody.appRoles) {
                        $AppCopyBody.appRoles = @(foreach ($Role in $AppCopyBody.api.appRoles) {
                                $Role | Select-Object * -ExcludeProperty 'isPreAuthorizationRequired', 'isPrivate'
                            })
                    }
                    if ($AppCopyBody.api -and $AppCopyBody.api.tokenEncryptionSetting) {
                        # Remove token encryption settings if property exists
                        $AppCopyBody.api.PSObject.Properties.Remove('tokenEncryptionSetting')
                    }

                    $NewApp = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/applications' -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -type POST -body ($AppCopyBody | ConvertTo-Json -Depth 10)

                    if (-not $NewApp) {
                        throw 'Failed to copy app registration to partner tenant'
                    }

                    Write-Information "App Registration copied. New AppId: $($NewApp.appId)"
                    $App = $NewApp
                    $AppId = $NewApp.appId
                    Write-Information "Creating service principal for AppId: $AppId in partner tenant"
                    $Body = @{
                        appId = $AppId
                    }
                    $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -type POST -body ($Body | ConvertTo-Json -Depth 10)
                    Write-LogMessage -headers $Request.headers -API $APINAME -message "App Registration $($AppDetails.displayName) copied to partner tenant" -Sev 'Info'
                }
            }

            $Permissions = if ($App.requiredResourceAccess) { $App.requiredResourceAccess } else { @() }
        }

        # Transform requiredResourceAccess to the CIPP permission format
        # CIPP expects: { "resourceAppId": { "applicationPermissions": [], "delegatedPermissions": [] } }
        # Graph returns: [ { "resourceAppId": "...", "resourceAccess": [ { "id": "...", "type": "Role|Scope" } ] } ]
        $CIPPPermissions = @{}
        $PermissionSetId = $null
        $PermissionSetName = "$DisplayName (Auto-created)"

        if ($Permissions -and $Permissions.Count -gt 0) {
            # Build bulk requests to get all service principals efficiently using object IDs from cached list
            $BulkRequests = [System.Collections.Generic.List[object]]::new()
            $RequestIndex = 0
            $AppIdToRequestId = @{}

            foreach ($Resource in $Permissions) {
                $ResourceAppId = $Resource.resourceAppId

                # Find the service principal object ID from the cached list
                $ResourceSPInfo = $TenantInfo | Where-Object { $_.appId -eq $ResourceAppId } | Select-Object -First 1

                if ($ResourceSPInfo) {
                    $RequestId = "sp-$RequestIndex"
                    $AppIdToRequestId[$ResourceAppId] = $RequestId

                    # Use object ID to fetch full details with appRoles
                    $BulkRequests.Add([PSCustomObject]@{
                            id     = $RequestId
                            method = 'GET'
                            url    = "/servicePrincipals/$($ResourceSPInfo.id)?`$select=id,appId,displayName,appRoles,publishedPermissionScopes"
                        })
                    $RequestIndex++
                } else {
                    Write-LogMessage -headers $Request.headers -API $APINAME -message "Service principal not found in tenant for appId: $ResourceAppId" -sev 'Warn'
                }
            }

            # Execute bulk request to get all service principals at once (only if we have requests)
            if ($BulkRequests.Count -gt 0) {
                Write-Information "Fetching $($BulkRequests.Count) service principal(s) via bulk request"
                $BulkResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests $BulkRequests -NoAuthCheck $true -AsApp $true

                # Create lookup table for service principals by appId
                $SPLookup = @{}
                foreach ($Result in $BulkResults) {
                    if ($Result.status -eq 200 -and $Result.body) {
                        $SPLookup[$Result.body.appId] = $Result.body
                    }
                }
            } else {
                $SPLookup = @{}
            }

            # Now process permissions for each resource
            foreach ($Resource in $Permissions) {
                $ResourceAppId = $Resource.resourceAppId
                $AppPerms = [System.Collections.ArrayList]::new()
                $DelegatedPerms = [System.Collections.ArrayList]::new()

                $ResourceSP = $SPLookup[$ResourceAppId]

                if (!$ResourceSP) {
                    Write-LogMessage -headers $Request.headers -API $APINAME -message "Service principal not found for appId: $ResourceAppId - skipping permission translation" -sev 'Warn'
                    continue
                }

                #Write-Information ($ResourceSP | ConvertTo-Json -Depth 10)

                foreach ($Access in $Resource.resourceAccess) {
                    if ($Access.type -eq 'Role') {
                        # Look up application permission name from appRoles
                        $AppRole = $ResourceSP.appRoles | Where-Object { $_.id -eq $Access.id } | Select-Object -First 1
                        if ($AppRole) {
                            $PermObj = [PSCustomObject]@{
                                id    = $Access.id
                                value = $AppRole.value  # Use the claim value name, not the GUID
                            }
                            [void]$AppPerms.Add($PermObj)
                        } else {
                            Write-LogMessage -headers $Request.headers -API $APINAME -message "Application permission $($Access.id) not found in $ResourceAppId appRoles" -sev 'Warn'
                        }
                    } elseif ($Access.type -eq 'Scope') {
                        Write-Information "Processing delegated permission with id $($Access.id) for resource appId $ResourceAppId"
                        # Try to look up the permission by ID in publishedPermissionScopes
                        $OAuth2Permission = $ResourceSP.publishedPermissionScopes | Where-Object { $_.id -eq $Access.id } | Select-Object -First 1
                        $OAuth2PermissionValue = $ResourceSP.publishedPermissionScopes | Where-Object { $_.value -eq $Access.id } | Select-Object -First 1
                        if ($OAuth2Permission) {
                            Write-Information "Found delegated permission in publishedPermissionScopes with value: $($OAuth2Permission.value)"
                            # Found the permission - use the value from the lookup
                            $PermObj = [PSCustomObject]@{
                                id    = $Access.id
                                value = $OAuth2Permission.value
                            }
                            [void]$DelegatedPerms.Add($PermObj)
                        } else {
                            # Not found by ID - assume Access.id is already the permission name
                            Write-Information "Could not find delegated permission by ID - using provided ID as value: $($Access.id)"
                            Write-Information "OAuth2PermissionValueLookup: $($OAuth2PermissionValue | ConvertTo-Json -Depth 10)"
                            $PermObj = [PSCustomObject]@{
                                id    = $OAuth2PermissionValue.id ?? $Access.id
                                value = $Access.id
                            }
                            [void]$DelegatedPerms.Add($PermObj)
                        }
                    }
                }

                $CIPPPermissions[$ResourceAppId] = [PSCustomObject]@{
                    applicationPermissions = @($AppPerms)
                    delegatedPermissions   = @($DelegatedPerms)
                }
            }

            # Permission set ID will be determined after template lookup
            $PermissionSetId = $null
        }

        # Get permissions table reference (needed later)
        $PermissionsTable = Get-CIPPTable -TableName 'AppPermissions'

        # Create the template
        $Table = Get-CIPPTable -TableName 'templates'

        # Check if template already exists
        # For servicePrincipal: match by AppId (immutable)
        # For application: match by DisplayName (since AppId changes when copied)
        $ExistingTemplate = $null
        if ($Overwrite) {
            try {
                $Filter = "PartitionKey eq 'AppApprovalTemplate'"
                $AllTemplates = Get-CIPPAzDataTableEntity @Table -Filter $Filter
                $TemplateNameToMatch = "$DisplayName (Auto-created)"

                foreach ($Template in $AllTemplates) {
                    $TemplateData = $Template.JSON | ConvertFrom-Json
                    $IsMatch = $false

                    if ($Type -eq 'servicePrincipal') {
                        # Match by AppId for service principals
                        $IsMatch = $TemplateData.AppId -eq $AppId
                    } else {
                        # Match by TemplateName for app registrations
                        $IsMatch = $TemplateData.TemplateName -eq $TemplateNameToMatch
                    }

                    if ($IsMatch) {
                        $ExistingTemplate = $Template
                        # Reuse the existing permission set ID if it exists
                        if ($TemplateData.PermissionSetId) {
                            $PermissionSetId = $TemplateData.PermissionSetId
                            Write-LogMessage -headers $Request.headers -API $APINAME -message "Found existing permission set ID: $PermissionSetId in template" -Sev 'Info'
                        } else {
                            Write-LogMessage -headers $Request.headers -API $APINAME -message 'Existing template found but has no PermissionSetId' -sev 'Warn'
                        }
                        break
                    }
                }
            } catch {
                # Ignore lookup errors
                Write-LogMessage -headers $Request.headers -API $APINAME -message "Error during template lookup: $($_.Exception.Message)" -sev 'Warn'
            }
        }

        if ($ExistingTemplate) {
            $TemplateId = $ExistingTemplate.RowKey
            $MatchCriteria = if ($Type -eq 'servicePrincipal') { "AppId: $AppId" } else { "DisplayName: $DisplayName" }
            Write-LogMessage -headers $Request.headers -API $APINAME -message "Overwriting existing template matched by $MatchCriteria (Template ID: $TemplateId)" -Sev 'Info'
            if ($PermissionSetId) {
                Write-LogMessage -headers $Request.headers -API $APINAME -message "Reusing permission set ID: $PermissionSetId" -Sev 'Info'
            }
        } else {
            $TemplateId = (New-Guid).Guid
        }

        # Create new permission set ID if we don't have one yet
        if (-not $PermissionSetId) {
            $PermissionSetId = (New-Guid).Guid
            Write-LogMessage -headers $Request.headers -API $APINAME -message "Creating new permission set ID: $PermissionSetId" -Sev 'Info'
        }

        # Now create/update the permission set entity with the determined ID
        if ($Permissions -and $Permissions.Count -gt 0) {
            $PermissionEntity = @{
                'PartitionKey' = 'Templates'
                'RowKey'       = [string]$PermissionSetId
                'TemplateName' = [string]$PermissionSetName
                'Permissions'  = [string]($CIPPPermissions | ConvertTo-Json -Depth 10 -Compress)
                'UpdatedBy'    = [string]'CIPP-API'
            }

            Add-CIPPAzDataTableEntity @PermissionsTable -Entity $PermissionEntity -Force
            Write-LogMessage -headers $Request.headers -API $APINAME -message "Permission set saved with ID: $PermissionSetId for $($Permissions.Count) resource(s)" -Sev 'Info'
        }

        $TemplateJson = @{
            TemplateName      = "$DisplayName (Auto-created)"
            AppId             = $AppId
            AppName           = $DisplayName
            AppType           = 'EnterpriseApp'
            Permissions       = $CIPPPermissions
            PermissionSetId   = $PermissionSetId
            PermissionSetName = $PermissionSetName
            AutoCreated       = $true
            SourceTenant      = $TenantFilter
            CreatedDate       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        } | ConvertTo-Json -Depth 10 -Compress

        $Entity = @{
            JSON         = "$TemplateJson"
            RowKey       = "$TemplateId"
            PartitionKey = 'AppApprovalTemplate'
        }

        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

        $PermissionCount = 0
        if ($CIPPPermissions -and $CIPPPermissions.Count -gt 0) {
            foreach ($ResourceAppId in $CIPPPermissions.Keys) {
                $Resource = $CIPPPermissions[$ResourceAppId]
                if ($Resource.applicationPermissions) {
                    $PermissionCount = $PermissionCount + $Resource.applicationPermissions.Count
                }
                if ($Resource.delegatedPermissions) {
                    $PermissionCount = $PermissionCount + $Resource.delegatedPermissions.Count
                }
            }
        }

        $Action = if ($ExistingTemplate) { 'updated' } else { 'created' }
        $Message = "Template $($Action) - $DisplayName with $PermissionCount permission(s)"
        Write-LogMessage -headers $Request.headers -API $APINAME -message $Message -Sev 'Info'

        $Body = @{
            Results  = @{'resultText' = $Message; 'state' = 'success' }
            Metadata = @{
                TemplateId   = $TemplateId
                SourceTenant = $TenantFilter
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Request.headers -API $APINAME -message "Failed to create template: $ErrorMessage" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        Write-Warning "Failed to create template: $ErrorMessage"
        Write-Information $_.InvocationInfo.PositionMessage

        $Body = @{
            Results = @(@{
                    resultText = "Failed to create template: $ErrorMessage"
                    state      = 'error'
                    details    = Get-CippException -Exception $_
                })
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ($Body | ConvertTo-Json -Depth 10)
        })
}

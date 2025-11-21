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
    Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Body.TenantFilter
        $AppId = $Request.Body.AppId
        $DisplayName = $Request.Body.DisplayName
        $Type = $Request.Body.Type # 'servicePrincipal' or 'application'

        if ([string]::IsNullOrWhiteSpace($AppId)) {
            throw 'AppId is required'
        }

        if ([string]::IsNullOrWhiteSpace($DisplayName)) {
            throw 'DisplayName is required'
        }

        # Get the app details based on type
        if ($Type -eq 'servicePrincipal') {
            # For enterprise apps (service principals)
            $AppDetails = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,appId,displayName,appRoles,oauth2PermissionScopes,requiredResourceAccess" -tenantid $TenantFilter

            if (-not $AppDetails -or $AppDetails.Count -eq 0) {
                throw "Service principal not found for AppId: $AppId"
            }

            $App = $AppDetails[0]

            # Get the application registration to access requiredResourceAccess
            try {
                $AppRegistration = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$filter=appId eq '$AppId'&`$select=id,appId,displayName,requiredResourceAccess" -tenantid $TenantFilter
                if ($AppRegistration -and $AppRegistration.Count -gt 0) {
                    $RequiredResourceAccess = $AppRegistration[0].requiredResourceAccess
                } else {
                    $RequiredResourceAccess = @()
                }
            } catch {
                Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message "Could not retrieve app registration for $AppId - will extract from service principal" -Sev 'Warning'
                $RequiredResourceAccess = @()
            }

            # Use requiredResourceAccess if available, otherwise we can't create a proper template
            if ($RequiredResourceAccess -and $RequiredResourceAccess.Count -gt 0) {
                $Permissions = $RequiredResourceAccess
            } else {
                # No permissions found - warn the user
                Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message "No permissions found for $AppId. The app registration may not have configured API permissions." -Sev 'Warning'
                $Permissions = @()
            }
        } else {
            # For app registrations (applications)
            $AppDetails = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$filter=appId eq '$AppId'&`$select=id,appId,displayName,requiredResourceAccess" -tenantid $TenantFilter
            if (-not $AppDetails -or $AppDetails.Count -eq 0) {
                throw "Application not found for AppId: $AppId"
            }
            $App = $AppDetails[0]
            $Permissions = if ($App.requiredResourceAccess) { $App.requiredResourceAccess } else { @() }
        }

        # Transform requiredResourceAccess to the CIPP permission format
        # CIPP expects: { "resourceAppId": { "applicationPermissions": [], "delegatedPermissions": [] } }
        # Graph returns: [ { "resourceAppId": "...", "resourceAccess": [ { "id": "...", "type": "Role|Scope" } ] } ]
        $CIPPPermissions = @{}
        $PermissionSetId = $null
        $PermissionSetName = "$DisplayName (Auto-created)"

        if ($Permissions -and $Permissions.Count -gt 0) {
            foreach ($Resource in $Permissions) {
                $ResourceAppId = $Resource.resourceAppId
                $AppPerms = [System.Collections.ArrayList]::new()
                $DelegatedPerms = [System.Collections.ArrayList]::new()

                foreach ($Access in $Resource.resourceAccess) {
                    $PermObj = [PSCustomObject]@{
                        id    = $Access.id
                        value = $Access.id  # In the permission set format, both id and value are the permission ID
                    }

                    if ($Access.type -eq 'Role') {
                        [void]$AppPerms.Add($PermObj)
                    } elseif ($Access.type -eq 'Scope') {
                        [void]$DelegatedPerms.Add($PermObj)
                    }
                }

                $CIPPPermissions[$ResourceAppId] = [PSCustomObject]@{
                    applicationPermissions = @($AppPerms)
                    delegatedPermissions   = @($DelegatedPerms)
                }
            }

            # Create the permission set in AppPermissions table
            $PermissionSetId = (New-Guid).Guid
            $PermissionsTable = Get-CIPPTable -TableName 'AppPermissions'

            $PermissionEntity = @{
                'PartitionKey' = 'Templates'
                'RowKey'       = [string]$PermissionSetId
                'TemplateName' = [string]$PermissionSetName
                'Permissions'  = [string]($CIPPPermissions | ConvertTo-Json -Depth 10 -Compress)
                'UpdatedBy'    = [string]'CIPP-API'
            }

            Add-CIPPAzDataTableEntity @PermissionsTable -Entity $PermissionEntity -Force
            Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message "Permission set created with ID: $PermissionSetId for $($Permissions.Count) resource(s)" -Sev 'Info'
        }

        # Create the template
        $Table = Get-CIPPTable -TableName 'templates'
        $TemplateId = (New-Guid).Guid

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

        Add-CIPPAzDataTableEntity @Table -Entity $Entity

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

        $Message = "Template created: $DisplayName with $PermissionCount permission(s)"
        Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message $Message -Sev 'Info'

        $Body = @{
            Results    = $Message
            TemplateId = $TemplateId
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create template: $ErrorMessage" -Sev 'Error'

        $Body = @{
            Results = "Failed to create template: $ErrorMessage"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ($Body | ConvertTo-Json -Depth 10)
        })
}

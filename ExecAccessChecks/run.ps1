using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
if ($Request.query.Permissions -eq 'true') {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Started permissions check' -Sev 'Debug'
    $Messages = [System.Collections.Generic.List[string]]::new()
    $MissingPermissions = [System.Collections.Generic.List[string]]::new()
    $Links = [System.Collections.Generic.List[object]]::new()
    $AccessTokenDetails = [PSCustomObject]@{
        AppId             = ''
        AppName           = ''
        Audience          = ''
        AuthMethods       = ''
        IPAddress         = ''
        Name              = ''
        Scope             = ''
        TenantId          = ''
        UserPrincipalName = ''
    }
    $Success = $true
    try {
        Set-Location (Get-Item $PSScriptRoot).Parent.FullName
        $ExpectedPermissions = Get-Content '.\Cache_SAMSetup\SAMManifest.json' | ConvertFrom-Json

        $GraphToken = Get-GraphToken -returnRefresh $true
        if ($GraphToken) {
            $GraphPermissions = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/myorganization/applications?`$filter=appId eq '$env:ApplicationID'" -NoAuthCheck $true
        }
        if ($env:MSI_SECRET) {
            try {
                Disable-AzContextAutosave -Scope Process | Out-Null
                $AzSession = Connect-AzAccount -Identity

                $KV = $ENV:WEBSITE_DEPLOYMENT_ID
                $KeyVaultRefresh = Get-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -AsPlainText
                if ($ENV:RefreshToken -ne $KeyVaultRefresh) {
                    $Success = $false
                    $Messages.Add('Your refresh token does not match key vault, clear your cache or wait 30 minutes.') | Out-Null
                    $Links.Add([PSCustomObject]@{
                            Text = 'Clear Token Cache'
                            Href = 'https://cipp.app/docs/general/troubleshooting/#clear-token-cache'
                        }
                    ) | Out-Null
                } else {
                    $Messages.Add('Your refresh token matches key vault.') | Out-Null
                }
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Key vault exception: $($_) " -Sev 'Error'
            }
        }

        try {
            $AccessTokenDetails = Read-JwtAccessDetails -Token $GraphToken.access_token -erroraction SilentlyContinue
        } catch {
            $AccessTokenDetails = [PSCustomObject]@{
                Name        = ''
                AuthMethods = @()
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Token exception: $($_) " -Sev 'Error'
            $Success = $false
        }

        if ($AccessTokenDetails.Name -eq '') {
            $Messages.Add('Your refresh token is invalid, check for line breaks or missing characters.') | Out-Null
            $Success = $false
        } else {
            if ($AccessTokenDetails.AuthMethods -contains 'mfa') {
                $Messages.Add('Your access token contains the MFA claim.') | Out-Null
            } else {
                $Messages.Add('Your access token does not contain the MFA claim, Refresh your SAM tokens.') | Out-Null
                $Success = $false
                $Links.Add([PSCustomObject]@{
                        Text = 'MFA Troubleshooting'
                        Href = 'https://cipp.app/docs/general/troubleshooting/#multi-factor-authentication-troubleshooting'
                    }
                ) | Out-Null
            }
        }

        $MissingPermissions = $ExpectedPermissions.requiredResourceAccess.ResourceAccess.id | Where-Object { $_ -notin $GraphPermissions.requiredResourceAccess.ResourceAccess.id }
        if ($MissingPermissions) {
            $Translator = Get-Content '.\Cache_SAMSetup\PermissionsTranslator.json' | ConvertFrom-Json
            $TranslatedPermissions = $Translator | Where-Object id -In $MissingPermissions | ForEach-Object { "$($_.value) - $($_.Origin)" }
            $MissingPermissions = @($TranslatedPermissions)
            $Success = $false
            $Links.Add([PSCustomObject]@{
                    Text = 'Permissions'
                    Href = 'https://cipp.app/docs/user/gettingstarted/postinstall/permissions/'
                }
            ) | Out-Null
        } else {
            $Messages.Add('Your Secure Application Model has all required permissions') | Out-Null
        }
        $CIPPGroupCount = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/`$count?`$filter=startsWith(displayName,'M365 GDAP')" -NoAuthCheck $true -ComplexFilter
        $SAMUserMemberships = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/me/memberOf?$select=id,displayName,isAssignableToRole' -NoAuthCheck $true
        $ExpectedGroups = @(
            'AdminAgents',
            'M365 GDAP Application Administrator',
            'M365 GDAP User Administrator',
            'M365 GDAP Intune Administrator',
            'M365 GDAP Exchange Administrator',
            'M365 GDAP Security Administrator',
            'M365 GDAP Cloud App Security Administrator',
            'M365 GDAP Cloud Device Administrator',
            'M365 GDAP Teams Administrator',
            'M365 GDAP Sharepoint Administrator',
            'M365 GDAP Authentication Policy Administrator',
            'M365 GDAP Privileged Role Administrator',
            'M365 GDAP Privileged Authentication Administrator'
        )
        $RoleAssignableGroups = $SAMUserMemberships | Where-Object { $_.isAssignableToRole }
        $NestedGroups = foreach ($Group in $RoleAssignableGroups) {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($Group.id)/memberOf?`$select=id,displayName" -NoAuthCheck $true
        }

        $MissingGroups = [System.Collections.Generic.List[string]]::new()
        foreach ($Group in $ExpectedGroups) {
            $GroupFound = $false
            foreach ($Membership in ($SAMUserMemberships + $NestedGroups)) {
                if ($Membership.displayName -match $Group -and (($CIPPGroupCount -gt 0 -and $Group -match 'M365 GDAP') -or $Group -notmatch 'M365 GDAP')) {
                    $GroupFound = $true
                }
            }
            if (-not $GroupFound) {
                $MissingGroups.Add($Group)
            }
        }
        if (($MissingGroups | Measure-Object).Count -eq 0) {
            $Messages.Add('The SAM user has all the required groups')
        } else {
            $Success = $false
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Permissions check failed: $($_) " -Sev 'Error'
        $Messages.Add("We could not connect to the API to retrieve the permissions. There might be a problem with the secure application model configuration. The returned error is: $(Get-NormalizedError -message $_)") | Out-Null
        $Success = $false
    }

    $Results = [PSCustomObject]@{
        AccessTokenDetails = $AccessTokenDetails
        Messages           = @($Messages)
        MissingPermissions = @($MissingPermissions)
        MissingGroups      = @($MissingGroups)
        Memberships        = @($SAMUserMemberships)
        CIPPGroupCount     = $CIPPGroupCount
        Links              = @($Links)
        Success            = $Success
    }
}

if ($Request.query.Tenants -eq 'true') {
    $ExpectedRoles = @(
        @{ Name = 'Application Administrator'; Id = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' },
        @{ Name = 'User Administrator'; Id = 'fe930be7-5e62-47db-91af-98c3a49a38b1' },
        @{ Name = 'Intune Administrator'; Id = '3a2c62db-5318-420d-8d74-23affee5d9d5' },
        @{ Name = 'Exchange Administrator'; Id = '29232cdf-9323-42fd-ade2-1d097af3e4de' },
        @{ Name = 'Security Administrator'; Id = '194ae4cb-b126-40b2-bd5b-6091b380977d' },
        @{ Name = 'Cloud App Security Administrator'; Id = '892c5842-a9a6-463a-8041-72aa08ca3cf6' },
        @{ Name = 'Cloud Device Administrator'; Id = '7698a772-787b-4ac8-901f-60d6b08affd2' },
        @{ Name = 'Teams Administrator'; Id = '69091246-20e8-4a56-aa4d-066075b2a7a8' },
        @{ Name = 'Sharepoint Administrator'; Id = 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c' },
        @{ Name = 'Authentication Policy Administrator'; Id = '0526716b-113d-4c15-b2c8-68e3c22b9f80' },
        @{ Name = 'Privileged Role Administrator'; Id = 'e8611ab8-c189-46e8-94e1-60213ab1f814' },
        @{ Name = 'Privileged Authentication Administrator'; Id = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13' }
    )
    $Tenants = ($Request.body.tenantid).split(',')
    if (!$Tenants) { $results = 'Could not load the tenants list from cache. Please run permissions check first, or visit the tenants page.' }
    $TenantList = Get-Tenants
    $TenantIds = foreach ($Tenant in $Tenants) {
        ($TenantList | Where-Object { $_.defaultDomainName -eq $Tenant }).customerId
    }
    $MyRoles = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/myRoles?`$filter=tenantId in ('$($TenantIds -join "','")')"
    $results = foreach ($tenant in $Tenants) {
        $AddedText = ''
        try {
            $TenantId = ($TenantList | Where-Object { $_.defaultDomainName -eq $tenant }).customerId
            $Assignments = ($MyRoles | Where-Object { $_.tenantId -eq $TenantId }).assignments
            $SAMUserRoles = ($Assignments | Where-Object { $_.assignmentType -eq 'granularDelegatedAdminPrivileges' }).roles

            $BulkRequests = $ExpectedRoles | ForEach-Object { @(
                    @{
                        id     = "roleManagement_$($_.id)"
                        method = 'GET'
                        url    = "roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$($_.id)'&`$expand=principal"
                    }
                )
            }
            $GDAPRolesGraph = New-GraphBulkRequest -tenantid $tenant -Requests $BulkRequests
            $GDAPRoles = [System.Collections.Generic.List[object]]::new()
            $MissingRoles = [System.Collections.Generic.List[object]]::new()
            foreach ($RoleId in $ExpectedRoles) {
                $GraphRole = $GDAPRolesGraph.body.value | Where-Object -Property roleDefinitionId -EQ $RoleId.Id
                $Role = $GraphRole.principal | Where-Object -Property organizationId -EQ $ENV:tenantid
                $SAMRole = $SAMUserRoles | Where-Object -Property templateId -EQ $RoleId.Id
                if (!$Role) {
                    $MissingRoles.Add(
                        [PSCustomObject]@{
                            Name = $RoleId.Name
                            Type = 'Tenant'
                        }
                    )
                    $AddedText = 'but missing GDAP roles'
                } else {
                    $GDAPRoles.Add([PSCustomObject]$RoleId)
                }
                if (!$SAMRole) {
                    $MissingRoles.Add(
                        [PSCustomObject]@{
                            Name = $RoleId.Name
                            Type = 'SAM User'
                        }
                    )
                    $AddedText = 'but missing GDAP roles'
                }
            }
            if (!($MissingRoles | Measure-Object).Count -gt 0) {
                $MissingRoles = $true
            }
            @{
                TenantName   = "$($Tenant)"
                Status       = "Successfully connected $($AddedText)"
                GDAPRoles    = $GDAPRoles
                MissingRoles = $MissingRoles
                SAMUserRoles = $SAMUserRoles
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message 'Tenant access check executed successfully' -Sev 'Info'

        } catch {
            @{
                TenantName = "$($tenant)"
                Status     = "Failed to connect: $(Get-NormalizedError -message $_.Exception.Message)"
                GDAP       = ''
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Tenant access check failed: $(Get-NormalizedError -message $_) " -Sev 'Error'

        }

        try {
            $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' -ErrorAction Stop
            @{
                TenantName = "$($Tenant)"
                Status     = 'Successfully connected to Exchange'
            }

        } catch {
            $ReportedError = ($_.ErrorDetails | ConvertFrom-Json -ErrorAction SilentlyContinue)
            $Message = if ($ReportedError.error.details.message) { $ReportedError.error.details.message } else { $ReportedError.error.innererror.internalException.message }
            if ($null -eq $Message) { $Message = $($_.Exception.Message) }
            @{
                TenantName = "$($Tenant)"
                Status     = "Failed to connect to Exchange: $(Get-NormalizedError -message $Message)"
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Tenant access check for Exchange failed: $(Get-NormalizedError -message $Message) " -Sev 'Error'
        }
    }
    if (!$Tenants) { $results = 'Could not load the tenants list from cache. Please run permissions check first, or visit the tenants page.' }
}

$body = [pscustomobject]@{'Results' = $Results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

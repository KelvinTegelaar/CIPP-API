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
        $ExpectedPermissions = @(
            'Application.Read.All', 'Application.ReadWrite.All', 'AuditLog.Read.All', 'Channel.Create', 'Channel.Delete.All', 'Channel.ReadBasic.All', 'ChannelMember.Read.All', 'ChannelMember.ReadWrite.All', 'ChannelMessage.Edit', 'ChannelMessage.Read.All', 'ChannelMessage.Send', 'ChannelSettings.Read.All', 'ChannelSettings.ReadWrite.All', 'ConsentRequest.Read.All', 'Device.Command', 'Device.Read', 'Device.Read.All', 'DeviceManagementApps.ReadWrite.All', 'DeviceManagementManagedDevices.PrivilegedOperations.All', 'DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementManagedDevices.ReadWrite.All', 'DeviceManagementRBAC.ReadWrite.All', 'DeviceManagementServiceConfig.ReadWrite.All', 'Directory.AccessAsUser.All', 'Domain.Read.All', 'Group.ReadWrite.All', 'GroupMember.ReadWrite.All', 'Mail.Send', 'Mail.Send.Shared', 'Member.Read.Hidden', 'Organization.ReadWrite.All', 'Policy.ReadWrite.ApplicationConfiguration' , 'Policy.Read.All', 'Policy.ReadWrite.AuthenticationFlows', 'Policy.ReadWrite.AuthenticationMethod', 'Policy.ReadWrite.Authorization', 'Policy.ReadWrite.ConsentRequest', 'Policy.ReadWrite.DeviceConfiguration', 'PrivilegedAccess.Read.AzureResources', 'PrivilegedAccess.ReadWrite.AzureResources', 'Reports.Read.All', 'RoleManagement.ReadWrite.Directory', 'SharePointTenantSettings.ReadWrite.All' , 'SecurityActions.ReadWrite.All', 'SecurityEvents.ReadWrite.All', 'SecurityIncident.Read.All', 'SecurityIncident.ReadWrite.All', 'ServiceHealth.Read.All', 'ServiceMessage.Read.All', 'Sites.ReadWrite.All', 'Team.Create', 'Team.ReadBasic.All', 'TeamMember.ReadWrite.All', 'TeamMember.ReadWriteNonOwnerRole.All', 'TeamsActivity.Read', 'TeamsActivity.Send', 'TeamsAppInstallation.ReadForChat', 'TeamsAppInstallation.ReadForTeam', 'TeamsAppInstallation.ReadForUser', 'TeamsAppInstallation.ReadWriteForChat', 'TeamsAppInstallation.ReadWriteForTeam', 'TeamsAppInstallation.ReadWriteForUser', 'TeamsAppInstallation.ReadWriteSelfForChat', 'TeamsAppInstallation.ReadWriteSelfForTeam', 'TeamsAppInstallation.ReadWriteSelfForUser', 'TeamSettings.Read.All', 'TeamSettings.ReadWrite.All', 'TeamsTab.Create', 'TeamsTab.Read.All', 'TeamsTab.ReadWrite.All', 'TeamsTab.ReadWriteForChat', 'TeamsTab.ReadWriteForTeam', 'TeamsTab.ReadWriteForUser', 'ThreatAssessment.ReadWrite.All', 'UnifiedGroupMember.Read.AsGuest', 'User.ManageIdentities.All', 'User.Read', 'User.ReadWrite.All', 'UserAuthenticationMethod.Read.All', 'UserAuthenticationMethod.ReadWrite', 'UserAuthenticationMethod.ReadWrite.All'
        )
        $GraphToken = Get-GraphToken -returnRefresh $true
        if ($GraphToken) {
            $GraphPermissions = $GraphToken.scope.split(' ') -replace 'https://graph.microsoft.com//', '' | Where-Object { $_ -notin @('email', 'openid', 'profile', '.default') }
        }
        if ($env:MSI_SECRET) {
            try {
                Disable-AzContextAutosave -Scope Process | Out-Null
                $AzSession = Connect-AzAccount -Identity

                $KV = $ENV:WEBSITE_DEPLOYMENT_ID
                $KeyVaultRefresh = Get-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -AsPlainText
                if ($ENV:RefreshToken -ne $KeyVaultRefresh) {
                    $Success = $false
                    $Messages.Add('Your refresh token does not match key vault, follow the Clear Token Cache procedure.') | Out-Null
                    $Links.Add([PSCustomObject]@{
                            Text = 'Clear Token Cache'
                            Href = 'https://cipp.app/docs/general/troubleshooting/#clear-token-cache'
                        }
                    ) | Out-Null
                }
                else {
                    $Messages.Add('Your refresh token matches key vault.') | Out-Null
                }
            }
            catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Key vault exception: $($_) " -Sev 'Error'
            }
        }

        try {
            $AccessTokenDetails = Read-JwtAccessDetails -Token $GraphToken.access_token -erroraction SilentlyContinue
        }
        catch {
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
        }
        else {
            if ($AccessTokenDetails.AuthMethods -contains 'mfa') {
                $Messages.Add('Your access token contains the MFA claim.') | Out-Null
            }
            else {
                $Messages.Add('Your access token does not contain the MFA claim, Refresh your SAM tokens.') | Out-Null
                $Success = $false
                $Links.Add([PSCustomObject]@{
                        Text = 'MFA Troubleshooting'
                        Href = 'https://cipp.app/docs/general/troubleshooting/#multi-factor-authentication-troubleshooting'
                    }
                ) | Out-Null
            }
        }
        
        $MissingPermissions = $ExpectedPermissions | Where-Object { $_ -notin $GraphPermissions } 
        if ($MissingPermissions) {
            $MissingPermissions = @($MissingPermissions)
            $Success = $false
            $Links.Add([PSCustomObject]@{
                    Text = 'Permissions'
                    Href = 'https://cipp.app/docs/user/gettingstarted/permissions/#permissions'
                }
            ) | Out-Null
        }
        else {
            $Messages.Add('Your Secure Application Model has all required permissions') | Out-Null
        }
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Permissions check failed: $($_) " -Sev 'Error'
        $Messages.Add("We could not connect to the API to retrieve the permissions. There might be a problem with the secure application model configuration. The returned error is: $(Get-NormalizedError -message $_)") | Out-Null
        $Success = $false
    }

    $Results = [PSCustomObject]@{
        AccessTokenDetails = $AccessTokenDetails
        Messages           = @($Messages)
        MissingPermissions = @($MissingPermissions)
        Links              = @($Links)
        Success            = $Success
    }
}

if ($Request.query.Tenants -eq 'true') {
    $Tenants = ($Request.body.tenantid).split(',')
    if (!$Tenants) { $results = 'Could not load the tenants list from cache. Please run permissions check first, or visit the tenants page.' }
    $results = foreach ($tenant in $Tenants) {
        try {
            $token = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/Organization' -tenantid $tenant
            @{
                TenantName = "$($Tenant)"
                Status     = 'Successfully connected' 
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message 'Tenant access check executed successfully' -Sev 'Info'

        }
        catch {
            @{
                TenantName = "$($tenant)"
                Status     = "Failed to connect to $(Get-NormalizedError -message $_.Exception.Message)" 
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Tenant access check failed: $(Get-NormalizedError -message $_) " -Sev 'Error'

        }

        try {
            $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' -ErrorAction Stop
            @{ 
                TenantName = "$($Tenant)"
                Status     = 'Successfully connected to Exchange'
            }

        }
        catch {
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

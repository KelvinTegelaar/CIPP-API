function Test-CIPPAccessPermissions {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = "Access Check",
        $ExecutingUser
    )
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
    Write-Host "Setting success to true by default."
    $Success = $true
    try {
        Set-Location (Get-Item $PSScriptRoot).FullName
        $ExpectedPermissions = Get-Content '.\SAMManifest.json' | ConvertFrom-Json

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
                    Write-Host "Setting success to false due to nonmaching token."

                    $Success = $false
                    $Messages.Add('Your refresh token does not match key vault, clear your cache or wait 30 minutes.') | Out-Null
                    $Links.Add([PSCustomObject]@{
                            Text = 'Clear Token Cache'
                            Href = 'https://docs.cipp.app/setup/installation/cleartokencache'
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
            Write-Host "Setting success to false due to not able to decode token."

        }

        if ($AccessTokenDetails.Name -eq '') {
            $Messages.Add('Your refresh token is invalid, check for line breaks or missing characters.') | Out-Null
            Write-Host "Setting success to false invalid token."

            $Success = $false
        }
        else {
            if ($AccessTokenDetails.AuthMethods -contains 'mfa') {
                $Messages.Add('Your access token contains the MFA claim.') | Out-Null
            }
            else {
                $Messages.Add('Your access token does not contain the MFA claim, Refresh your SAM tokens.') | Out-Null
                Write-Host "Setting success to False due to invalid list of claims."

                $Success = $false
                $Links.Add([PSCustomObject]@{
                        Text = 'MFA Troubleshooting'
                        Href = 'https://docs.cipp.app/troubleshooting/troubleshooting#multi-factor-authentication-troubleshooting'
                    }
                ) | Out-Null
            }
        }

        $MissingPermissions = $ExpectedPermissions.requiredResourceAccess.ResourceAccess.id | Where-Object { $_ -notin $GraphPermissions.requiredResourceAccess.ResourceAccess.id }
        if ($MissingPermissions) {
            Write-Host "Setting success to False due to permissions issues: $($MissingPermissions | ConvertTo-Json)"

            $Translator = Get-Content '.\PermissionsTranslator.json' | ConvertFrom-Json
            $TranslatedPermissions = $Translator | Where-Object id -In $MissingPermissions | ForEach-Object { "$($_.value) - $($_.Origin)" }
            $MissingPermissions = @($TranslatedPermissions)
            $Success = $false
            $Links.Add([PSCustomObject]@{
                    Text = 'Permissions'
                    Href = 'https://docs.cipp.app/setup/installation/permissions'
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
        Write-Host "Setting success to False due to not being able to connect."

        $Success = $false
    }

    return [PSCustomObject]@{
        AccessTokenDetails = $AccessTokenDetails
        Messages           = @($Messages)
        MissingPermissions = @($MissingPermissions)
        Links              = @($Links)
        Success            = $Success
    }
}

function Invoke-ExecSAMSetup {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .LEGACY
        This function is a legacy function that was used to set up the CIPP application in Azure AD. It is not used in the current version of CIPP, look at Invoke-ExecCreateSAMApp for the new version.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    if ($Request.Query.error) {
        Add-Type -AssemblyName System.Web
        return ([HttpResponseContext]@{
                ContentType = 'text/html'
                StatusCode  = [HttpStatusCode]::Forbidden
                Body        = Get-normalizedError -Message [System.Web.HttpUtility]::UrlDecode($Request.Query.error_description)
            })
        exit
    }
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
        if (!$Secret) {
            $Secret = [PSCustomObject]@{
                'PartitionKey'      = 'Secret'
                'RowKey'            = 'Secret'
                'TenantId'          = ''
                'RefreshToken'      = ''
                'ApplicationId'     = ''
                'ApplicationSecret' = ''
            }
            Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
        }
    }
    if (!$env:SetFromProfile) {
        Write-Information "We're reloading from KV"
        Get-CIPPAuthentication
    }

    $KV = $env:WEBSITE_DEPLOYMENT_ID
    $Table = Get-CIPPTable -TableName SAMWizard
    $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-10)

    try {
        if ($Request.Query.count -lt 1 ) { $Results = 'No authentication code found. Please go back to the wizard.' }

        if ($Request.Body.setkeys) {
            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                if ($Request.Body.TenantId) { $Secret.TenantId = $Request.Body.tenantid }
                if ($Request.Body.RefreshToken) { $Secret.RefreshToken = $Request.Body.RefreshToken }
                if ($Request.Body.applicationid) { $Secret.ApplicationId = $Request.Body.ApplicationId }
                if ($Request.Body.ApplicationSecret) { $Secret.ApplicationSecret = $Request.Body.ApplicationSecret }
                Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
            } else {
                if ($Request.Body.tenantid) { Set-CippKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $Request.Body.tenantid -AsPlainText -Force) }
                if ($Request.Body.RefreshToken) { Set-CippKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Request.Body.RefreshToken -AsPlainText -Force) }
                if ($Request.Body.applicationid) { Set-CippKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Request.Body.applicationid -AsPlainText -Force) }
                if ($Request.Body.applicationsecret) { Set-CippKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $Request.Body.applicationsecret -AsPlainText -Force) }
            }

            $Results = @{ Results = 'The keys have been replaced. Please perform a permissions check.' }
        }
        if ($Request.Query.error -eq 'invalid_client') { $Results = 'Client ID was not found in Azure. Try waiting 10 seconds to try again, if you have gotten this error after 5 minutes, please restart the process.' }
        if ($Request.Query.code) {
            try {
                $TenantId = $Rows.tenantid
                if (!$TenantId -or $TenantId -eq 'NotStarted') { $TenantId = $env:TenantID }
                $AppID = $Rows.appid
                if (!$AppID -or $AppID -eq 'NotStarted') { $appid = $env:ApplicationID }
                $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $clientsecret = $Secret.ApplicationSecret
                } else {
                    $clientsecret = Get-CippKeyVaultSecret -VaultName $kv -Name 'ApplicationSecret' -AsPlainText
                }
                if (!$clientsecret) { $clientsecret = $env:ApplicationSecret }
                Write-Information "client_id=$appid&scope=https://graph.microsoft.com/.default+offline_access+openid+profile&code=$($Request.Query.code)&grant_type=authorization_code&redirect_uri=$($url)&client_secret=$clientsecret" #-Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
                $RefreshToken = Invoke-RestMethod -Method POST -Body "client_id=$appid&scope=https://graph.microsoft.com/.default+offline_access+openid+profile&code=$($Request.Query.code)&grant_type=authorization_code&redirect_uri=$($url)&client_secret=$clientsecret" -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -ContentType 'application/x-www-form-urlencoded'

                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $Secret.RefreshToken = $RefreshToken.refresh_token
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                } else {
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $RefreshToken.refresh_token -AsPlainText -Force)
                }

                $Results = 'Authentication is now complete. You may now close this window.'
                try {
                    $SetupPhase = $rows.validated = $true
                    Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                } catch {
                    #no need.
                }
            } catch {
                $Results = "Authentication failed. $($_.Exception.message)"
            }
        }
        if ($Request.Query.CreateSAM) {
            $Rows = @{
                RowKey       = 'setup'
                PartitionKey = 'setup'
                validated    = $false
                SamSetup     = 'NotStarted'
                partnersetup = $true
                appid        = 'NotStarted'
                tenantid     = 'NotStarted'
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
            $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-10)
            $step = 1
            $DeviceLogon = New-DeviceLogin -clientid '1b730954-1685-4b74-9bfd-dac224a7b894' -Scope 'https://graph.microsoft.com/.default' -FirstLogon
            $SetupPhase = $rows.SamSetup = [string]($DeviceLogon | ConvertTo-Json)
            Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
            $Results = @{ code = $($DeviceLogon.user_code); message = "Your code is $($DeviceLogon.user_code). Enter the code"  ; step = $step; url = $DeviceLogon.verification_uri }
        }
        if ($Request.Query.CheckSetupProcess -and $Request.Query.step -eq 1) {
            $SAMSetup = $Rows.SamSetup | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($SamSetup.token_type -eq 'Bearer') {
                #sleeping for 10 seconds to allow the token to be created.
                Start-Sleep 10
                #nulling the token to force a recheck.
                $step = 2
            }
            $Token = (New-DeviceLogin -clientid '1b730954-1685-4b74-9bfd-dac224a7b894' -Scope 'https://graph.microsoft.com/.default' -device_code $SAMSetup.device_code)
            Write-Information "Token is $($token | ConvertTo-Json)"
            if ($Token.access_token) {
                $step = 2
                $rows.SamSetup = [string]($Token | ConvertTo-Json)
                $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                $PartnerSetup = $true
                $TenantId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/organization' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method GET -ContentType 'application/json').value.id
                $SetupPhase = $rows.tenantid = [string]($TenantId)
                Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                if ($PartnerSetup) {
                    #$app = Get-Content '.\Cache_SAMSetup\SAMManifest.json' | ConvertFrom-Json
                    $ModuleBase = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
                    $SamManifestFile = Get-Item (Join-Path $ModuleBase 'lib\data\SAMManifest.json')
                    $app = Get-Content $SamManifestFile.FullName | ConvertFrom-Json

                    $App.web.redirectUris = @($App.web.redirectUris + $URL)
                    $app = $app | ConvertTo-Json -Depth 15
                    $AppId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/applications' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body $app -ContentType 'application/json')
                    $rows.appid = [string]($AppId.appId)
                    Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                    $attempt = 0
                    do {
                        try {
                            try {
                                $SPNDefender = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"fc780465-2017-40d4-a0c5-307022471b92`" }" -ContentType 'application/json')
                            } catch {
                                Write-Information "didn't deploy spn for defender, probably already there."
                            }
                            try {
                                $SPNTeams = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"48ac35b8-9aa8-4d74-927d-1f4a14a0b239`" }" -ContentType 'application/json')
                            } catch {
                                Write-Information "didn't deploy spn for Teams, probably already there."
                            }
                            try {
                                $SPNO365Manage = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"c5393580-f805-4401-95e8-94b7a6ef2fc2`" }" -ContentType 'application/json')
                            } catch {
                                Write-Information "didn't deploy spn for O365 Management, probably already there."
                            }
                            try {
                                $SPNPartnerCenter = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd`" }" -ContentType 'application/json')
                            } catch {
                                Write-Information "didn't deploy spn for PartnerCenter, probably already there."
                            }
                            $SPN = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"$($AppId.appId)`" }" -ContentType 'application/json')
                            Start-Sleep 3
                            $attempt ++
                        } catch {
                            $attempt ++
                        }
                    } until ($attempt -gt 5)
                }
                $AppPassword = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications/$($AppId.id)/addPassword" -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body '{"passwordCredential":{"displayName":"CIPPInstall"}}' -ContentType 'application/json').secretText
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $Secret.TenantId = $TenantId
                    $Secret.ApplicationId = $AppId.appId
                    $Secret.ApplicationSecret = $AppPassword
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                    Write-Information ($Secret | ConvertTo-Json -Depth 5)
                } else {
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $TenantId -AsPlainText -Force)
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Appid.appId -AsPlainText -Force)
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $AppPassword -AsPlainText -Force)
                }
                $Results = @{'message' = 'Created application. Waiting 30 seconds for Azure propagation'; step = $step }
            } else {
                $step = 1
                $Results = @{ code = $($SAMSetup.user_code); message = "Your code is $($SAMSetup.user_code). Enter the code "  ; step = $step; url = $SAMSetup.verification_uri }
            }

        }
        switch ($Request.Query.step) {
            2 {
                $step = 2
                $TenantId = $Rows.tenantid
                $AppID = $rows.appid
                $PartnerSetup = $true
                $SetupPhase = $rows.SamSetup = [string]($FirstLogonRefreshtoken | ConvertTo-Json)
                Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                $Validated = $Rows.validated
                if ($Validated) { $step = 3 }
                $Results = @{ appId = $AppID; message = 'Give the next approval by clicking ' ; step = $step; url = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?scope=https://graph.microsoft.com/.default+offline_access+openid+profile&response_type=code&client_id=$($appid)&redirect_uri=$($url)" }
            }
            3 {
                $step = 4
                $Results = @{'message' = 'Received token.'; step = $step }
            }
            4 {
                Remove-AzDataTableEntity -Force @Table -Entity $Rows
                $step = 5
                $Results = @{'message' = 'setup completed.'; step = $step
                }
            }
        }

    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.InvocationInfo.ScriptLineNumber):  $($_.Exception.message)" ; step = $step }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}

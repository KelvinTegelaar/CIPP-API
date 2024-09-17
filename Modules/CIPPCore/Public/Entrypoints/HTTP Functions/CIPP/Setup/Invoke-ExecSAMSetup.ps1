using namespace System.Net

Function Invoke-ExecSAMSetup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $UserCreds = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json)
    if ($Request.Query.error) {
        Add-Type -AssemblyName System.Web
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                ContentType = 'text/html'
                StatusCode  = [HttpStatusCode]::Forbidden
                Body        = Get-normalizedError -Message [System.Web.HttpUtility]::UrlDecode($Request.Query.error_description)
            })
        exit
    }
    if ('admin' -notin $UserCreds.userRoles) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                ContentType = 'text/html'
                StatusCode  = [HttpStatusCode]::Forbidden
                Body        = 'Could not find an admin cookie in your browser. Make sure you do not have an adblocker active, use a Chromium browser, and allow cookies. If our automatic refresh does not work, try pressing the URL bar and hitting enter. We will try to refresh ourselves in 3 seconds.<meta http-equiv="refresh" content="3" />'
            })
        exit
    }

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
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
    } else {
        if ($env:MSI_SECRET) {
            Disable-AzContextAutosave -Scope Process | Out-Null
            $AzSession = Connect-AzAccount -Identity
        }
    }
    if (!$ENV:SetFromProfile) {
        Write-Host "We're reloading from KV"
        Get-CIPPAuthentication
    }

    $KV = $ENV:WEBSITE_DEPLOYMENT_ID
    $Table = Get-CIPPTable -TableName SAMWizard
    $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-10)

    try {
        if ($Request.Query.count -lt 1 ) { $Results = 'No authentication code found. Please go back to the wizard.' }

        if ($Request.Body.setkeys) {
            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                if ($Request.Body.TenantId) { $Secret.TenantId = $Request.Body.tenantid }
                if ($Request.Body.RefreshToken) { $Secret.RefreshToken = $Request.Body.RefreshToken }
                if ($Request.Body.applicationid) { $Secret.ApplicationId = $Request.Body.ApplicationId }
                if ($Request.Body.ApplicationSecret) { $Secret.ApplicationSecret = $Request.Body.ApplicationSecret }
                Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
            } else {
                if ($Request.Body.tenantid) { Set-AzKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $Request.Body.tenantid -AsPlainText -Force) }
                if ($Request.Body.RefreshToken) { Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Request.Body.RefreshToken -AsPlainText -Force) }
                if ($Request.Body.applicationid) { Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Request.Body.applicationid -AsPlainText -Force) }
                if ($Request.Body.applicationsecret) { Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $Request.Body.applicationsecret -AsPlainText -Force) }
            }
            $Results = @{ Results = 'The keys have been replaced. Please perform a permissions check.' }
        }
        if ($Request.Query.error -eq 'invalid_client') { $Results = 'Client ID was not found in Azure. Try waiting 10 seconds to try again, if you have gotten this error after 5 minutes, please restart the process.' }
        if ($Request.Query.code) {
            try {
                $TenantId = $Rows.tenantid
                if (!$TenantId) { $TenantId = $ENV:TenantId }
                $AppID = $Rows.appid
                if (!$AppID) { $appid = $env:ApplicationId }
                $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                    $clientsecret = $Secret.ApplicationSecret
                } else {
                    $clientsecret = Get-AzKeyVaultSecret -VaultName $kv -Name 'ApplicationSecret' -AsPlainText
                }
                if (!$clientsecret) { $clientsecret = $ENV:ApplicationSecret }
                Write-Host "client_id=$appid&scope=https://graph.microsoft.com/.default+offline_access+openid+profile&code=$($Request.Query.code)&grant_type=authorization_code&redirect_uri=$($url)&client_secret=$clientsecret" -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
                $RefreshToken = Invoke-RestMethod -Method POST -Body "client_id=$appid&scope=https://graph.microsoft.com/.default+offline_access+openid+profile&code=$($Request.Query.code)&grant_type=authorization_code&redirect_uri=$($url)&client_secret=$clientsecret" -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -ContentType 'application/x-www-form-urlencoded'

                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                    $Secret.RefreshToken = $RefreshToken.refresh_token
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                } else {
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $RefreshToken.refresh_token -AsPlainText -Force)
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
                partnersetup = $false
                appid        = 'NotStarted'
                tenantid     = 'NotStarted'
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
            $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-10)

            if ($Request.Query.partnersetup) {
                $SetupPhase = $Rows.partnersetup = $true
                Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
            }
            $step = 1
            $DeviceLogon = New-DeviceLogin -clientid '1b730954-1685-4b74-9bfd-dac224a7b894' -Scope 'https://graph.microsoft.com/.default' -FirstLogon
            $SetupPhase = $rows.SamSetup = [string]($DeviceLogon | ConvertTo-Json)
            Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
            $Results = @{ message = "Your code is $($DeviceLogon.user_code). Enter the code"  ; step = $step; url = $DeviceLogon.verification_uri }
        }
        if ($Request.Query.CheckSetupProcess -and $Request.Query.step -eq 1) {
            $SAMSetup = $Rows.SamSetup | ConvertFrom-Json -ErrorAction SilentlyContinue
            $Token = (New-DeviceLogin -clientid '1b730954-1685-4b74-9bfd-dac224a7b894' -Scope 'https://graph.microsoft.com/.default' -device_code $SAMSetup.device_code)
            if ($Token.access_token) {
                $step = 2
                $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                $PartnerSetup = $Rows.partnersetup
                $TenantId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/organization' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method GET -ContentType 'application/json').value.id
                $SetupPhase = $rows.tenantid = [string]($TenantId)
                Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                if ($PartnerSetup) {
                    $app = Get-Content '.\Cache_SAMSetup\SAMManifest.json' | ConvertFrom-Json
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
                                Write-Host "didn't deploy spn for defender, probably already there."
                            }
                            try {
                                $SPNTeams = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"48ac35b8-9aa8-4d74-927d-1f4a14a0b239`" }" -ContentType 'application/json')
                            } catch {
                                Write-Host "didn't deploy spn for Teams, probably already there."
                            }
                            try {
                                $SPNO365Manage = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"c5393580-f805-4401-95e8-94b7a6ef2fc2`" }" -ContentType 'application/json')
                            } catch {
                                Write-Host "didn't deploy spn for O365 Management, probably already there."
                            }
                            try {
                                $SPNPartnerCenter = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd`" }" -ContentType 'application/json')
                            } catch {
                                Write-Host "didn't deploy spn for PartnerCenter, probably already there."
                            }
                            $SPN = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"$($AppId.appId)`" }" -ContentType 'application/json')
                            Start-Sleep 3
                            $GroupID = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'AdminAgents')" -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method Get -ContentType 'application/json').value.id
                            Write-Host "Id is $GroupID"
                            $AddingToAdminAgent = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/groups/$($GroupID)/members/`$ref" -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"@odata.id`": `"https://graph.microsoft.com/v1.0/directoryObjects/$($SPN.id)`"}" -ContentType 'application/json')
                            Write-Host 'Added to adminagents'
                            $attempt ++
                        } catch {
                            $attempt ++
                        }
                    } until ($attempt -gt 5)
                } else {
                    $app = Get-Content '.\Cache_SAMSetup\SAMManifestNoPartner.json'
                    $AppId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/applications' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body $app -ContentType 'application/json')
                    $Rows.appid = [string]($AppId.appId)
                    Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                }
                $AppPassword = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications/$($AppId.id)/addPassword" -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body '{"passwordCredential":{"displayName":"CIPPInstall"}}' -ContentType 'application/json').secretText


                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                    $Secret.TenantId = $TenantId
                    $Secret.ApplicationId = $AppId.appId
                    $Secret.ApplicationSecret = $AppPassword
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                    Write-Information ($Secret | ConvertTo-Json -Depth 5)
                } else {
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $TenantId -AsPlainText -Force)
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Appid.appId -AsPlainText -Force)
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $AppPassword -AsPlainText -Force)
                }
                $Results = @{'message' = 'Created application. Waiting 30 seconds for Azure propagation'; step = $step }
            } else {
                $step = 1
                $Results = @{ message = "Your code is $($SAMSetup.user_code). Enter the code "  ; step = $step; url = $SAMSetup.verification_uri }
            }

        }
        switch ($Request.Query.step) {
            2 {
                $step = 2
                $TenantId = $Rows.tenantid
                $AppID = $rows.appid
                $PartnerSetup = $Rows.partnersetup
                $SetupPhase = $rows.SamSetup = [string]($FirstLogonRefreshtoken | ConvertTo-Json)
                Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                $Validated = $Rows.validated
                if ($Validated) { $step = 3 }
                $Results = @{ message = 'Give the next approval by clicking '  ; step = $step; url = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?scope=https://graph.microsoft.com/.default+offline_access+openid+profile&response_type=code&client_id=$($appid)&redirect_uri=$($url)" }
            }
            3 {

                $step = 4
                $Results = @{'message' = 'Received token.'; step = $step }


            }
            4 {
                Remove-AzDataTableEntity @Table -Entity $Rows

                $step = 5
                $Results = @{'message' = 'setup completed.'; step = $step
                }
            }
        }

    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.InvocationInfo.ScriptLineNumber):  $($_.Exception.message)" ; step = $step }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}

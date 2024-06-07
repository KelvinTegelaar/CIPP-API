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
    if ($Request.query.error) {
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
        if ($Request.query.count -lt 1 ) { $Results = 'No authentication code found. Please go back to the wizard.' }

        if ($request.body.setkeys) {
            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                if ($request.body.TenantId) { $Secret.TenantId = $Request.body.tenantid }
                if ($request.body.RefreshToken) { $Secret.RefreshToken = $Request.body.RefreshToken }
                if ($request.body.applicationid) { $Secret.ApplicationId = $Request.body.ApplicationId }
                if ($request.body.ApplicationSecret) { $Secret.ApplicationSecret = $Request.body.ApplicationSecret }
                Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
            } else {
                if ($request.body.tenantid) { Set-AzKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $request.body.tenantid -AsPlainText -Force) }
                if ($request.body.RefreshToken) { Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $request.body.RefreshToken -AsPlainText -Force) }
                if ($request.body.applicationid) { Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $request.body.applicationid -AsPlainText -Force) }
                if ($request.body.applicationsecret) { Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $request.body.applicationsecret -AsPlainText -Force) }
            }
            $Results = @{ Results = 'The keys have been replaced. Please perform a permissions check.' }
        }
        if ($Request.query.error -eq 'invalid_client') { $Results = 'Client ID was not found in Azure. Try waiting 10 seconds to try again, if you have gotten this error after 5 minutes, please restart the process.' }
        if ($request.query.code) {
            try {
                $TenantId = $Rows.tenantid
                if (!$TenantId) { $TenantId = $ENV:TenantId }
                $AppID = $Rows.appid
                if (!$AppID) { $appid = $env:ApplicationId }
                $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                    $clientsecret = $Secret.ApplicationSecret
                } else {
                    $clientsecret = Get-AzKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -AsPlainText
                }
                if (!$clientsecret) { $clientsecret = $ENV:ApplicationSecret }
                Write-Host "client_id=$appid&scope=https://graph.microsoft.com/.default+offline_access+openid+profile&code=$($request.query.code)&grant_type=authorization_code&redirect_uri=$($url)&client_secret=$clientsecret" -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
                $RefreshToken = Invoke-RestMethod -Method POST -Body "client_id=$appid&scope=https://graph.microsoft.com/.default+offline_access+openid+profile&code=$($request.query.code)&grant_type=authorization_code&redirect_uri=$($url)&client_secret=$clientsecret" -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

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
        if ($request.query.CreateSAM) {
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

            if ($Request.query.partnersetup) {
                $SetupPhase = $Rows.partnersetup = $true
                Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
            }
            $step = 1
            $DeviceLogon = New-DeviceLogin -clientid '1b730954-1685-4b74-9bfd-dac224a7b894' -Scope 'https://graph.microsoft.com/.default' -FirstLogon
            $SetupPhase = $rows.SamSetup = [string]($DeviceLogon | ConvertTo-Json)
            Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
            $Results = @{ message = "Your code is $($DeviceLogon.user_code). Enter the code"  ; step = $step; url = $DeviceLogon.verification_uri }
        }
        if ($Request.query.CheckSetupProcess -and $request.query.step -eq 1) {
            $SAMSetup = $Rows.SamSetup | ConvertFrom-Json -ErrorAction SilentlyContinue
            $Token = (New-DeviceLogin -clientid '1b730954-1685-4b74-9bfd-dac224a7b894' -Scope 'https://graph.microsoft.com/.default' -device_code $SAMSetup.device_code)
            if ($token.Access_Token) {
                $step = 2
                $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                $PartnerSetup = $Rows.partnersetup
                $TenantId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/organization' -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method GET -ContentType 'application/json').value.id
                $SetupPhase = $rows.tenantid = [string]($TenantId)
                Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                if ($PartnerSetup) {
                    $app = Get-Content '.\Cache_SAMSetup\SAMManifest.json' | ConvertFrom-Json
                    $App.web.redirectUris = @($App.web.redirectUris + $URL)
                    $app = $app | ConvertTo-Json -Depth 15
                    $AppId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/applications' -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body $app -ContentType 'application/json')
                    $rows.appid = [string]($AppId.appId)
                    Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                    $attempt = 0
                    do {
                        try {
                            try {
                                $SPNDefender = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body "{ `"appId`": `"fc780465-2017-40d4-a0c5-307022471b92`" }" -ContentType 'application/json')
                            } catch {
                                Write-Host "didn't deploy spn for defender, probably already there."
                            }
                            try {
                                $SPNTeams = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body "{ `"appId`": `"48ac35b8-9aa8-4d74-927d-1f4a14a0b239`" }" -ContentType 'application/json')
                            } catch {
                                Write-Host "didn't deploy spn for Teams, probably already there."
                            }
                            try {
                                $SPNPartnerCenter = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body "{ `"appId`": `"fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd`" }" -ContentType 'application/json')
                            } catch {
                                Write-Host "didn't deploy spn for PartnerCenter, probably already there."
                            }
                            $SPN = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body "{ `"appId`": `"$($AppId.appId)`" }" -ContentType 'application/json')
                            Start-Sleep 3
                            $GroupID = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'AdminAgents')" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method Get -ContentType 'application/json').value.id
                            Write-Host "Id is $GroupID"
                            $AddingToAdminAgent = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/groups/$($GroupID)/members/`$ref" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body "{ `"@odata.id`": `"https://graph.microsoft.com/v1.0/directoryObjects/$($SPN.id)`"}" -ContentType 'application/json')
                            Write-Host 'Added to adminagents'
                            $attempt ++
                        } catch {
                            $attempt ++
                        }
                    } until ($attempt -gt 5)
                } else {
                    $app = Get-Content '.\Cache_SAMSetup\SAMManifestNoPartner.json'
                    $AppId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/applications' -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body $app -ContentType 'application/json')
                    $rows.appid = [string]($AppId.appId)
                    Add-CIPPAzDataTableEntity @Table -Entity $Rows -Force | Out-Null
                }
                $AppPassword = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications/$($AppID.id)/addPassword" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body '{"passwordCredential":{"displayName":"CIPPInstall"}}' -ContentType 'application/json').secretText


                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                    $Secret.TenantId = $Request.body.tenantid
                    $Secret.ApplicationId = $Request.body.ApplicationId
                    $Secret.ApplicationSecret = $Request.body.ApplicationSecret
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                } else {
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $TenantId -AsPlainText -Force)
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Appid.appid -AsPlainText -Force)
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $AppPassword -AsPlainText -Force)
                }
                $Results = @{'message' = 'Created application. Waiting 30 seconds for Azure propagation'; step = $step }
            } else {
                $step = 1
                $Results = @{ message = "Your code is $($SAMSetup.user_code). Enter the code "  ; step = $step; url = $SAMSetup.verification_uri }
            }

        }
        switch ($request.query.step) {
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

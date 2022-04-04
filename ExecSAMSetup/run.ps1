using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$ResourceGroup = $ENV:Website_Resource_Group
$Subscription = ($ENV:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1
if ($env:MSI_SECRET) {
      Disable-AzContextAutosave -Scope Process | Out-Null
      $AzSession = Connect-AzAccount -Identity -Subscription $Subscription
}
$KV = Get-AzKeyVault -SubscriptionID $Subscription -ResourceGroupName $ResourceGroup

try {
      if ($request.body.setkeys) {
            Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $request.body.tenantid -AsPlainText -Force)
            Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $request.body.RefreshToken -AsPlainText -Force)
            Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'ExchangeRefreshToken' -SecretValue (ConvertTo-SecureString -String $request.body.exchangeRefreshToken -AsPlainText -Force)
            Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $request.body.applicationid -AsPlainText -Force)
            Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $request.body.applicationsecret -AsPlainText -Force)
            $Results = @{ Results = "Replaced keys" }
      }
      if ($Request.query.count -lt 1 ) { $Results = "No authentication code found. Please go back to the wizard and click the URL again." }
      if ($Request.query.error -eq 'invalid_client') { $Results = "Client ID was not found in Azure. Try waiting 10 seconds to try again, if you have gotten this error after 5 minutes, please restart the process." }
      if ($request.query.code) {
            try {
                  $TenantId = Get-Content '.\Cache_SAMSetup\cache.tenantid'
                  $AppID = Get-Content '.\Cache_SAMSetup\cache.appid'
                  $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                  $clientsecret = Get-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'applicationsecret' -AsPlainText
                  $RefreshToken = Invoke-RestMethod -Method POST -Body "client_id=$appid&scope=https://graph.microsoft.com/.default+offline_access+openid+profile&code=$($request.query.code)&grant_type=authorization_code&redirect_uri=$($url)&client_secret=$clientsecret" -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
                  Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $RefreshToken.refresh_token -AsPlainText -Force)
                  $Results = "Authentication is now complete. You may now close this window."
                  New-Item ".\Cache_SAMSetup\Validated.json" -Value "true" -Force
            }
            catch {
                  $Results = "Authentication failed. $($_.Exception.message)"
            }
      }
      if ($request.query.CreateSAM) { 
            Remove-Item ".\Cache_SAMSetup\SamSetup.json" -Force -ErrorAction SilentlyContinue
            Remove-Item ".\Cache_SAMSetup\Cache.*" -Force -ErrorAction SilentlyContinue
            Remove-Item ".\Cache_SAMSetup\SamSetup.json" -Force -ErrorAction SilentlyContinue
            Remove-Item ".\Cache_SAMSetup\PartnerSetup.json" -Force -ErrorAction SilentlyContinue
            Remove-Item ".\Cache_SAMSetup\Validated.json"  -Force -ErrorAction SilentlyContinue
            if ($Request.query.partnersetup) { New-Item -Path '.\Cache_SAMSetup\PartnerSetup.json' -Value 'True' }
            $step = 1
            $DeviceLogon = New-DeviceLogin -clientid "1b730954-1685-4b74-9bfd-dac224a7b894" -Scope 'https://graph.microsoft.com/.default' -FirstLogon
            New-Item '.\Cache_SAMSetup\SamSetup.json' -Value ($DeviceLogon | ConvertTo-Json) -Force
            $Results = @{ message = "Your code is $($DeviceLogon.user_code). Enter the code"  ; step = $step; url = $DeviceLogon.verification_uri }
      }
      if ($Request.query.CheckSetupProcess -and $request.query.step -eq 1) {
            $SAMSetup = Get-Content '.\Cache_SAMSetup\SamSetup.json' | ConvertFrom-Json
            $Token = (New-DeviceLogin -clientid "1b730954-1685-4b74-9bfd-dac224a7b894" -Scope 'https://graph.microsoft.com/.default' -device_code $SAMSetup.device_code)
            if ($token.Access_Token) {
                  $step = 2
                  $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                  $PartnerSetup = Get-Content '.\Cache_SAMSetup\PartnerSetup.json' -ErrorAction SilentlyContinue
                  $TenantId = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/organization" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method GET -ContentType 'application/json').value.id
                  $TenantId | Out-File '.\Cache_SAMSetup\cache.tenantid' 
                  if ($PartnerSetup) {
                        $app = Get-Content '.\Cache_SAMSetup\SAMManifest.json' | ConvertFrom-Json
                        $App.web.redirectUris = @($App.web.redirectUris + $URL)
                        $app = $app | ConvertTo-Json -Depth 15
                        $AppId = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body $app -ContentType 'application/json')
                        $AppId.appId | Out-File '.\Cache_SAMSetup\cache.appid'
                        $attempt = 0
                        do {
                              try {
                                    Write-Host "{ `"appId`": `"$($AppId.appId)`" }" 
                                    $SPN = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/servicePrincipals" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body "{ `"appId`": `"$($AppId.appId)`" }" -ContentType 'application/json')
                                    Write-Host "SPN"
                                    Start-Sleep 3
                                    $GroupID = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'AdminAgents')" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method Get -ContentType 'application/json').value.id
                                    Write-Host "Id is $GroupID"
                                    $AddingToAdminAgent = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/groups/$($GroupID)/members/`$ref" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body "{ `"@odata.id`": `"https://graph.microsoft.com/v1.0/directoryObjects/$($SPN.id)`"}" -ContentType 'application/json')
                                    Write-Host "Added to adminagents"
                                    $attempt ++
                              }
                              catch {
                                    $attempt ++
                              }
                        } until ($attempt -gt 5)
                  }
                  else {
                        $app = Get-Content '.\Cache_SAMSetup\SAMManifestNoPartner.json'
                        $AppId = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body $app -ContentType 'application/json')
                        $AppId.appId | Out-File '.\Cache_SAMSetup\cache.appid'
                  }
                  $AppPassword = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications/$($AppID.id)/addPassword" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body '{"passwordCredential":{"displayName":"CIPPInstall"}}' -ContentType 'application/json').secretText
                  Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $TenantId -AsPlainText -Force)
                  Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Appid.appid -AsPlainText -Force)
                  Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $AppPassword -AsPlainText -Force)
                  $Results = @{"message" = "Created application. Waiting 30 seconds for Azure propagation"; step = $step }
            }
            else {
                  $step = 1
                  $Results = @{ message = "Your code is $($SAMSetup.user_code). Enter the code "  ; step = $step; url = $SAMSetup.verification_uri }            
            }
           
      }
      switch ($request.query.step) {
            2 {
                  $step = 2
                  $TenantId = Get-Content '.\Cache_SAMSetup\cache.tenantid'
                  $AppID = Get-Content '.\Cache_SAMSetup\cache.appid'
                  $PartnerSetup = Get-Content '.\Cache_SAMSetup\PartnerSetup.json' -ErrorAction SilentlyContinue  
                  New-Item '.\Cache_SAMSetup\SamSetup.json' -Value ($FirstLogonRefreshtoken | ConvertTo-Json) -Force
                  $URL = ($Request.headers.'x-ms-original-url').split('?') | Select-Object -First 1
                  $Validated = Get-Content ".\Cache_SAMSetup\Validated.json" -ErrorAction SilentlyContinue
                  if ($Validated) { $step = 3 }
                  $Results = @{ message = "Give the next approval by clicking "  ; step = $step; url = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?scope=https://graph.microsoft.com/.default+offline_access+openid+profile&response_type=code&client_id=$($appid)&redirect_uri=$($url)" }
            }
            3 {

                  $step = 4
                  $Results = @{"message" = "Received token."; step = $step }
                  
 
            }
            4 {
                  $step = 4
                  $TenantId = Get-Content '.\Cache_SAMSetup\cache.tenantid' 
                  $FirstExchangeLogonRefreshtoken = New-DeviceLogin -clientid 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -Scope 'https://outlook.office365.com/.default' -FirstLogon  -TenantId $TenantId
                  New-Item '.\Cache_SAMSetup\SamSetup.json' -Value ($FirstExchangeLogonRefreshtoken | ConvertTo-Json) -Force
                  $step = 5
                  $Results = @{ message = "Your code is $($FirstExchangeLogonRefreshtoken.user_code). Enter the code "  ; step = $step; url = $FirstExchangeLogonRefreshtoken.verification_uri }            
            }
            5 {
                  $step = 5
                  $TenantId = Get-Content '.\Cache_SAMSetup\cache.tenantid'
                  $SAMSetup = Get-Content '.\Cache_SAMSetup\SamSetup.json' | ConvertFrom-Json
                  $ExchangeRefreshToken = (New-DeviceLogin -clientid 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -Scope 'https://outlook.office365.com/.default' -device_code $SAMSetup.device_code)
                  if ($ExchangeRefreshToken.Refresh_Token) {
                        Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'exchangerefreshtoken' -SecretValue (ConvertTo-SecureString -String $ExchangeRefreshToken.Refresh_Token -AsPlainText -Force)
                        $step = 6
                        $Results = @{"message" = "Retrieved refresh token and saving to Keyvault."; step = $step }
                  }
                  else {
                        $Results = @{ message = "Your code is $($SAMSetup.user_code). Enter the code "  ; step = $step; url = $SAMSetup.verification_uri }            
                  }
            }
            6 {
                  Remove-Item ".\Cache_SAMSetup\Validated.json"  -Force -ErrorAction SilentlyContinue
                  Remove-Item ".\Cache_SAMSetup\SamSetup.json" -Force -ErrorAction SilentlyContinue
                  Remove-Item ".\Cache_SAMSetup\Cache.*" -Force -ErrorAction SilentlyContinue
                  Remove-Item ".\Cache_SAMSetup\SamSetup.json" -Force -ErrorAction SilentlyContinue
                  Remove-Item ".\Cache_SAMSetup\PartnerSetup.json" -Force -ErrorAction SilentlyContinue
                  $step = 7
                  $Results = @{"message" = "Installation completed."; step = $step
                  }
            }
      }

}
catch {
      $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.message)" ; step = $step }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })
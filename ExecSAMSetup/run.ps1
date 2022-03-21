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
      if ($request.query.CreateSAM) { 
            Remove-Item ".\Cache_SAMSetup\PartnerSetup.json" -Force -ErrorAction SilentlyContinue
            if ($Request.query.partnersetup) { New-Item -Path '.\Cache_SAMSetup\PartnerSetup.json' -Value 'True' }
            $step = 1
            $DeviceLogon = New-DeviceLogin -clientid "1b730954-1685-4b74-9bfd-dac224a7b894" -Scope 'https://graph.microsoft.com/.default' -FirstLogon
            New-Item '.\Cache_SAMSetup\SamSetup.json' -Value ($DeviceLogon | ConvertTo-Json) -Force
            $Results = @{ message = $DeviceLogon.message  ; step = $step }
      }
      if ($Request.query.CheckSetupProcess -and $request.query.step -eq 1) {
            $SAMSetup = Get-Content '.\Cache_SAMSetup\SamSetup.json' | ConvertFrom-Json
            $Token = (New-DeviceLogin -clientid "1b730954-1685-4b74-9bfd-dac224a7b894" -Scope 'https://graph.microsoft.com/.default' -device_code $SAMSetup.device_code)
            if ($token.Access_Token) {
                  $step = 2
                  
                  $PartnerSetup = Get-Content '.\Cache_SAMSetup\PartnerSetup.json' -ErrorAction SilentlyContinue
                  $TenantId = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/organization" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method GET -ContentType 'application/json').value.id
                  $TenantId | Out-File '.\Cache_SAMSetup\cache.tenantid' 
                  if ($PartnerSetup) {
                        $app = Get-Content '.\Cache_SAMSetup\SAMManifest.json'
                        $AppId = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body $app -ContentType 'application/json')
                        $AppId.appId | Out-File '.\Cache_SAMSetup\cache.appid'
                  }
                  else {
                        $app = Get-Content '.\Cache_SAMSetup\SAMManifestNoPartner.json'
                        $AppId = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body $app -ContentType 'application/json')
                        $AppId.appId | Out-File '.\Cache_SAMSetup\cache.appid'
                  }
                  Write-Host $AppId
                  $AppPassword = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications/$($AppID.id)/addPassword" -Headers @{ authorization = "Bearer $($Token.Access_Token)" } -Method POST -Body '{"passwordCredential":{"displayName":"CIPPInstall"}}' -ContentType 'application/json').secretText
                  Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $TenantId -AsPlainText -Force)
                  Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Appid.appid -AsPlainText -Force)
                  Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $AppPassword -AsPlainText -Force)
                  $Results = @{"message" = "Created application. Waiting 30 seconds for Azure propagation"; step = $step }
            }
            else {
                  $step = 1
                  $Results = @{"message" = $SAMSetup.message ; step = $step }
            }
           
      }
      switch ($request.query.step) {
            2 {
                  $step = 2
                  $TenantId = Get-Content '.\Cache_SAMSetup\cache.tenantid'
                  $AppID = Get-Content '.\Cache_SAMSetup\cache.appid'
                  $PartnerSetup = Get-Content '.\Cache_SAMSetup\PartnerSetup.json' -ErrorAction SilentlyContinue  
                  $FirstLogonRefreshtoken = New-DeviceLogin -clientid $AppID -Scope 'https://graph.microsoft.com/.default' -FirstLogon -TenantId $TenantId
                  New-Item '.\Cache_SAMSetup\SamSetup.json' -Value ($FirstLogonRefreshtoken | ConvertTo-Json) -Force
                  $step = 3
                  $Results = @{ message = $FirstLogonRefreshtoken.message  ; step = $step }
            }
            3 {
                  $step = 3
                  $SAMSetup = Get-Content '.\Cache_SAMSetup\SAMSetup.json' | ConvertFrom-Json
                  $TenantId = Get-Content '.\Cache_SAMSetup\cache.tenantid' 
                  $AppID = Get-Content '.\Cache_SAMSetup\cache.appid'  
                  $PartnerSetup = Get-Content '.\Cache_SAMSetup\PartnerSetup.json' -ErrorAction SilentlyContinue  
                  $RefreshToken = (New-DeviceLogin -clientid $AppID -Scope 'https://graph.microsoft.com/.default' -device_code $SAMSetup.device_code)

                  if ($RefreshToken.Refresh_Token) {
                        Set-AzKeyVaultSecret -VaultName $kv.vaultname -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $RefreshToken.Refresh_Token -AsPlainText -Force)
                        if ($PartnerSetup) {
                              $attempt = 0
                              do {
                                    try {
                                          Start-Sleep 3
                                          $GroupID = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'AdminAgents')" -Headers @{ authorization = "Bearer $($RefreshToken.Access_Token)" } -Method Get -ContentType 'application/json').value.id
                                          Write-Host "Id is $GroupID"
                                          $SPN = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($Appid)'" -Headers @{ authorization = "Bearer $($RefreshToken.Access_Token)" } -Method Get -ContentType 'application/json').value.id
                                          Write-Host "SPN is $SPN"
                                          $AddingToAdminAgent = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/groups/$($GroupID)/members/`$ref" -Headers @{ authorization = "Bearer $($RefreshToken.Access_Token)" } -Method POST -Body "{ `"@odata.id`": `"https://graph.microsoft.com/v1.0/directoryObjects/$($SPN)`"}" -ContentType 'application/json')
                                          Write-Host "Added to adminagents"
                                          $attempt ++
                                    }
                                    catch {
                                          $attempt ++
                                    }
                              } until ($attempt -gt 5)

                           

                        }
                        $step = 4
                        $Results = @{"message" = "Retrieved refresh token and saving to Keyvault."; step = $step }
                  }
                  else {
                        $step = 3
                        $Results = @{"message" = $SAMSetup.message ; step = $step }
                  }
            }
            4 {
                  $step = 4
                  $TenantId = Get-Content '.\Cache_SAMSetup\cache.tenantid' 
                  $FirstExchangeLogonRefreshtoken = New-DeviceLogin -clientid 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -Scope 'https://outlook.office365.com/.default' -FirstLogon  -TenantId $TenantId
                  New-Item '.\Cache_SAMSetup\SamSetup.json' -Value ($FirstExchangeLogonRefreshtoken | ConvertTo-Json) -Force
                  $step = 5
                  $Results = @{ message = $FirstExchangeLogonRefreshtoken.message  ; step = $step }
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
                        $Results = @{"message" = $SAMSetup.message ; step = $step }
                  }
            }
            6 {
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
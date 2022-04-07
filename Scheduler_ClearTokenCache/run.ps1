param($tenant)

$ResourceGroup = $ENV:Website_Resource_Group
$Subscription = ($ENV:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1
if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    $AzSession = Connect-AzAccount -Identity -Subscription $Subscription
}

$Function = Get-AzFunctionApp -ResourceGroupName $ResourceGroup -Name $ENV:WEBSITE_SITE_NAME

switch ($tenant) {
    'Phase1' {
        try {
            Log-request -API 'ClearTokenCache' -tenant 'Scheduler' -message 'Phase 1: Renaming settings and restarting function app' -sev Info
            $Settings = $Function | Get-AzFunctionAppSetting
            $Function | Update-AzFunctionAppSetting -AppSetting @{ 
                RefreshToken2         = $Settings.RefreshToken 
                ExchangeRefreshToken2 = $Settings.ExchangeRefreshToken
            }
            $Function | Remove-AzFunctionAppSetting -AppSettingName RefreshToken
            $Function | Remove-AzFunctionAppSetting -AppSettingName ExchangeRefreshToken

            [PSCustomObject]@{
                tenant = 'Phase2'
                Type   = 'ClearTokenCache'
            } | ConvertTo-Json -Compress | Out-File 'Cache_Scheduler\_ClearTokenCache.json' -Force

            $Function | Restart-AzFunctionApp -Confirm:$false
        }
        catch {
            Log-request -API 'ClearTokenCache' -tenant 'Scheduler' -message "Phase 1: Exception caught - $($_.Exception.Message)" -sev Error
            Remove-Item -Path 'Cache_Scheduler\_ClearTokenCache.json' -Force -Confirm:$false
        }
    }
    'Phase2' {
        try {
            Log-request -API 'ClearTokenCache' -tenant 'Scheduler' -message 'Phase 2: Waiting 5 minutes and restarting function app' -sev Info
            Start-Sleep -Seconds 300
        
            [PSCustomObject]@{
                tenant = 'Phase3'
                Type   = 'ClearTokenCache'
            } | ConvertTo-Json -Compress | Out-File 'Cache_Scheduler\_ClearTokenCache.json' -Force 
            $Function | Restart-AzFunctionApp -Confirm:$false
        }
        catch {
            Log-request -API 'ClearTokenCache' -tenant 'Scheduler' -message "Phase 2: Exception caught - $($_.Exception.Message)" -sev Error
            Remove-Item -Path 'Cache_Scheduler\_ClearTokenCache.json' -Force -Confirm:$false
        }
    }
    'Phase3' {
        try {
            Log-request -API 'ClearTokenCache' -tenant 'Scheduler' -message 'Phase 3: Waiting 5 minutes, renaming settings back and restarting function app' -sev Info

            Start-Sleep -Seconds 300
            $Settings = $Function | Get-AzFunctionAppSetting
            $Function | Update-AzFunctionAppSetting -AppSetting @{ 
                RefreshToken         = $Settings.RefreshToken2
                ExchangeRefreshToken = $Settings.ExchangeRefreshToken2
            }
            $Function | Remove-AzFunctionAppSetting -AppSettingName RefreshToken2
            $Function | Remove-AzFunctionAppSetting -AppSettingName ExchangeRefreshToken2

            [PSCustomObject]@{
                tenant = 'Phase4'
                Type   = 'ClearTokenCache'
            } | ConvertTo-Json -Compress | Out-File 'Cache_Scheduler\_ClearTokenCache.json' -Force 

            $Function | Restart-AzFunctionApp -Confirm:$false
        }
        catch {
            Log-request -API 'ClearTokenCache' -tenant 'Scheduler' -message "Phase 2: Exception caught - $($_.Exception.Message)" -sev Error
            Remove-Item -Path 'Cache_Scheduler\_ClearTokenCache.json' -Force -Confirm:$false
        }
    }
    'Phase4' {
        Log-request -API 'ClearTokenCache' -tenant 'Scheduler' -message 'Phase 4: Update token cache completed. Removing scheduler entry.' -sev Info
        Remove-Item 'Cache_Scheduler\_UpdateTokens.json' -Force -Confirm:$false
    }
}
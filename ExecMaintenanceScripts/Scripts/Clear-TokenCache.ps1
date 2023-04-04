$ResourceGroup = '##RESOURCEGROUP##'
$Subscription = '##SUBSCRIPTION##'
$FunctionName = '##FUNCTIONAPP##'

$Logo = @'
   _____ _____ _____  _____  
  / ____|_   _|  __ \|  __ \ 
 | |      | | | |__) | |__) |
 | |      | | |  ___/|  ___/ 
 | |____ _| |_| |    | |     
  \_____|_____|_|    |_|     
                
'@
Write-Host $Logo

function Start-SleepProgress($Seconds) {
    $doneDT = (Get-Date).AddSeconds($Seconds)
    while ($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity 'Sleeping' -Status 'Sleeping...' -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity 'Sleeping' -Status 'Sleeping...' -SecondsRemaining 0 -Completed
}

Write-Host '- Connecting to Azure'
Connect-AzAccount -Identity -Subscription $Subscription | Out-Null
$Function = Get-AzFunctionApp -ResourceGroupName $ResourceGroup -Name $FunctionName
try {
    Write-Host 'Phase 1: Renaming settings and stopping function app' 
    $Settings = $Function | Get-AzFunctionAppSetting
    $Function | Update-AzFunctionAppSetting -AppSetting @{ 
        RefreshToken2         = $Settings.RefreshToken 
    } | Out-Null
    $Function | Remove-AzFunctionAppSetting -AppSettingName RefreshToken | Out-Null
    $Function | Remove-AzFunctionAppSetting -AppSettingName ExchangeRefreshToken | Out-Null # Leave this in to clean up ExchangeRefreshToken entry
    $Function | Stop-AzFunctionApp -Force | Out-Null
}
catch {
    Write-Host "Phase 1: Exception caught - $($_.Exception.Message)"
    exit 1
}

try {
    Write-Host 'Phase 2: Waiting 5 minutes and starting function app'
    Start-SleepProgress -Seconds 300
    $Function | Start-AzFunctionApp | Out-Null
}
catch {
    Write-Host "Phase 2: Exception caught - $($_.Exception.Message)" 
    exit 1
}

try {
    Write-Host 'Phase 3: Changing settings back, stopping function app, waiting 5 minutes and restarting.'
    $Settings = $Function | Get-AzFunctionAppSetting
    $Function | Update-AzFunctionAppSetting -AppSetting @{ 
        RefreshToken         = $Settings.RefreshToken2
    } | Out-Null
    $Function | Stop-AzFunctionApp -Force | Out-Null
    Start-SleepProgress -Seconds 300
    $Function | Start-AzFunctionApp | Out-Null

    Write-Host 'Cleaning up temporary settings'
    $Function | Remove-AzFunctionAppSetting -AppSettingName RefreshToken2 | Out-Null
    $Function | Remove-AzFunctionAppSetting -AppSettingName ExchangeRefreshToken2 | Out-Null # Leave this in to deal with leftover ExchangeRefreshToken2 entries
    $Function | Restart-AzFunctionApp -Force | Out-Null
}
catch {
    Write-Host "Phase 3: Exception caught - $($_.Exception.Message)"
    exit 1
}
   
Write-Host '- Update token cache completed.'

param($tenant)
$ConnectionString = ($ENV:AzureWebJobsStorage).split(';') | ConvertFrom-StringData | ConvertTo-Json  | ConvertFrom-Json   
$Date = Get-Date
if ($date.hour -eq 23 -and $date.minute -le '9') {
    $context = New-AzStorageContext -StorageAccountName $($connectionstring.accountname | Select-Object -Last 1) -StorageAccountKey ($connectionstring.accountkey  | Select-Object -Last 1)
    Remove-AzStorageContainer -Context $context -Container "$($ENV:WEBSITE_CONTENTSHARE)-largemessages" -Force
    $InstancesTable = (Get-AzStorageTable -Context $context -Name "*instances").cloudTable
    #We leave 1 hour of results so current jobs can finish cleanly
    Get-AzTableRow -Table $InstancesTable |  Where-Object -Property TimeStamp -LT (Get-Date).addhours(-1) | Remove-AzTableRow -Table $InstancesTable
    #we remove the entire history daily, it gets rebuild as soon as a job runs.
    Get-AzStorageTable -Context $context -Name "*history" | Remove-AzStorageTable -Force
    #we delete the dashboard logs as they are no longer supported or required.
    Get-AzStorageTable -Context $context -Name "AzureWebJobsHostLogs*" | Remove-AzStorageTable -Force
}
else {
    "not my turn yet, waiting"
} 

param($tenant)
$ConnectionString = ($ENV:AzureWebJobsStorage).split(';') | ConvertFrom-StringData | ConvertTo-Json  | ConvertFrom-Json   
$Date = Get-Date
if ($date.hour -eq 23 -and $date.minute -le '9') {
    $context = New-AzStorageContext -StorageAccountName $($connectionstring.accountname | Select-Object -Last 1) -StorageAccountKey ($connectionstring.accountkey  | Select-Object -Last 1)
    Get-AzStorageBlob -Context $context -Container "$($ENV:WEBSITE_CONTENTSHARE)-largemessages" | Where-Object -Property LastModified -LT (Get-Date).addhours(-24) | Remove-AzStorageBlob
    $InstancesTable = (Get-AzStorageTable -Context $context -Name "*instances").cloudTable
    $HistoryTable = (Get-AzStorageTable -Context $context -Name "*history").cloudTable
    Get-AzTableRow -Table $InstancesTable | Where-Object -Property RunTimeStatus -NE "Running" | Remove-AzTableRow -Table $InstancesTable
    Get-AzTableRow -Table $HistoryTable | Where-Object -Property TimeStamp -LT (Get-Date).addhours(-24) | Remove-AzTableRow -Table $HistoryTable
    Get-AzStorageTable -Context $context -Name "AzureWebJobsHostLogs*" | Remove-AzStorageTable -Force
}
else {
    "not my turn yet, waiting"
} 

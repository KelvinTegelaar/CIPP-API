function Write-AlertMessage($message, $tenant = 'None', $tenantId = $null) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    #Do duplicate detection, if no duplicate, write.
    $Table = Get-CIPPTable -tablename CippLogs
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $Filter = "PartitionKey eq '{0}' and Message eq '{1}' and Tenant eq '{2}'" -f $PartitionKey, $message.Replace("'", "''"), $tenant
    $ExistingMessage = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    if (!$ExistingMessage) {
        Write-Host 'No duplicate message found, writing to log'
        Write-LogMessage -message $message -tenant $tenant -sev 'Alert' -tenantId $tenantId -API 'Alerts'
    } else {
        Write-Host 'Alerts: Duplicate entry found, not writing to log'

    }
}

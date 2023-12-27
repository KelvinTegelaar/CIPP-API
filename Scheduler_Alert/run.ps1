param($tenant)

try {

    $Table = Get-CIPPTable -Table SchedulerConfig
    if ($Tenant.tag -eq 'AllTenants') {
        $Filter = "RowKey eq 'AllTenants' and PartitionKey eq 'Alert'"
    } else {
        $Filter = "RowKey eq '{0}' and PartitionKey eq 'Alert'" -f $Tenant.tenantid
    }
    $Alerts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    
    $DeltaTable = Get-CIPPTable -Table DeltaCompare
    $LastRunTable = Get-CIPPTable -Table AlertLastRun
    $IgnoreList = @('Etag', 'PartitionKey', 'Timestamp', 'RowKey', 'tenantid', 'tenant', 'type')
    $alertList = $Alerts | Select-Object * -ExcludeProperty $IgnoreList 
    foreach ($task in ($AlertList.psobject.members | Where-Object { $_.MemberType -EQ 'NoteProperty' -and $_.value -eq $True }).name) {
        $QueueItem = [pscustomobject]@{
            tenant       = $tenant.tenant
            tenantid     = $tenant.tenantid
            DeltaTable   = $DeltaTable
            LastRunTable = $LastRunTable
            FunctionName = "CIPPAlert$($Task)"
        }
        Push-OutputBinding -Name QueueItem -Value $QueueItem
    }

    $Table = Get-CIPPTable
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $tenant.tenant
    $currentlog = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    $AlertsTable = Get-CIPPTable -Table cachealerts
    $CurrentAlerts = (Get-CIPPAzDataTableEntity @AlertsTable -Filter $Filter)
    $CurrentAlerts | ForEach-Object {
        if ($_.Message -notin $currentlog.Message) { Write-LogMessage -message $_.Message -API 'Alerts' -tenant $tenant.tenant -sev Alert -tenantid $Tenant.tenantid }
        Remove-AzDataTableEntity @AlertsTable -Entity $_
    }

    [PSCustomObject]@{
        ReturnedValues = $true
    }
} catch {
    $Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
    Write-LogMessage -message $Message -API 'Alerts' -tenant $tenant.tenant -sev Error
    [PSCustomObject]@{
        ReturnedValues = $false
    }
}

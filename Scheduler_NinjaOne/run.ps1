using namespace System.Net

param($Timer)

$Table = Get-CIPPTable -TableName NinjaOneSettings
$Settings = (Get-AzDataTableEntity @Table)
$TimeSetting = ($Settings | Where-Object { $_.RowKey -eq 'NinjaSyncTime' }).SettingValue

if (($TimeSetting | Measure-Object).count -ne 1) {
    $TimeSetting = Get-Random -Minimum 0 -Maximum 96
    $AddObject = @{
        PartitionKey   = 'NinjaConfig'
        RowKey         = 'NinjaSyncTime'
        'SettingValue' = $TimeSetting
    }
    Add-AzDataTableEntity @Table -Entity $AddObject -Force
}

$LastRunTime = ($Settings | Where-Object { $_.RowKey -eq 'NinjaLastRunTime' }).SettingValue
$CurrentInterval = ($currentHour * 4) + [math]::Floor($currentMinute / 15)

if ($Null -eq $LastRunTime -or $LastRunTime -le (Get-Date).addhours(-25) -or $TimeSetting -eq $CurrentInterval) {
    $CIPPMapping = Get-CIPPTable -TableName CippMapping
    $Filter = "PartitionKey eq 'NinjaOrgsMapping'"
    $TenantsToProcess = Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.NinjaOne -and $_.NinjaOne -ne '' }

    foreach ($Tenant in $TenantsToProcess) {
        Push-OutputBinding -Name NinjaProcess -Value @{
            'NinjaAction' = 'SyncTenant'
            'MappedTenant' = $Tenant
        }

    }

    $AddObject = @{
        PartitionKey   = 'NinjaConfig'
        RowKey         = 'NinjaLastRunTime'
        'SettingValue' = Get-Date
    }
    Add-AzDataTableEntity @Table -Entity $AddObject -Force
    
    Write-LogMessage -API 'NinjaOneAutoMap_Queue' -user 'CIPP' -message "NinjaOne Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" -Sev 'Info' 

}
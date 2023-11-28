using namespace System.Net

param($Timer)

$Table = Get-CIPPTable -TableName Extensionsconfig

$Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json)

Write-Host "Started Scheduler for Extensions"

# NinjaOne Extension
if ($Configuration.NinjaOne.Enabled -eq $True) {

    $Table = Get-CIPPTable -TableName NinjaOneSettings
    $Settings = (Get-AzDataTableEntity @Table)
    $TimeSetting = ($Settings | Where-Object { $_.RowKey -eq 'NinjaSyncTime' }).SettingValue

    

    if (($TimeSetting | Measure-Object).count -ne 1) {
        [int]$TimeSetting = Get-Random -Minimum 1 -Maximum 95
        $AddObject = @{
            PartitionKey   = 'NinjaConfig'
            RowKey         = 'NinjaSyncTime'
            'SettingValue' = $TimeSetting
        }
        Add-AzDataTableEntity @Table -Entity $AddObject -Force
    }

    Write-Host "Ninja Time Setting: $TimeSetting"

    $LastRunTime = Get-Date(($Settings | Where-Object { $_.RowKey -eq 'NinjaLastRunTime' }).SettingValue)

    Write-Host "Last Run: $LastRunTime"

    $CurrentTime = Get-Date
    $CurrentInterval = ($CurrentTime.Hour * 4) + [math]::Floor($CurrentTime.Minute / 15)

    Write-Host "Current Interval: $CurrentInterval"

    if ($Null -eq $LastRunTime -or $LastRunTime -le (Get-Date).addhours(-25) -or $TimeSetting -eq $CurrentInterval) {
        Write-Host "Executing"
        $CIPPMapping = Get-CIPPTable -TableName CippMapping
        $Filter = "PartitionKey eq 'NinjaOrgsMapping'"
        $TenantsToProcess = Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.NinjaOne -and $_.NinjaOne -ne '' }

        foreach ($Tenant in $TenantsToProcess) {
            Push-OutputBinding -Name NinjaProcess -Value @{
                'NinjaAction'  = 'SyncTenant'
                'MappedTenant' = $Tenant
            }

        }

        $AddObject = @{
            PartitionKey   = 'NinjaConfig'
            RowKey         = 'NinjaLastRunTime'
            'SettingValue' = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffK")
        }
        Add-AzDataTableEntity @Table -Entity $AddObject -Force
    
        Write-LogMessage -API 'NinjaOneAutoMap_Queue' -user 'CIPP' -message "NinjaOne Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" -Sev 'Info' 

    }
}
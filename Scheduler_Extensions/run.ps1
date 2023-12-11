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

    $CIPPMapping = Get-CIPPTable -TableName CippMapping
    $Filter = "PartitionKey eq 'NinjaOrgsMapping'"
    $TenantsToProcess = Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.NinjaOne -and $_.NinjaOne -ne '' }

    if ($Null -eq $LastRunTime -or $LastRunTime -le (Get-Date).addhours(-25) -or $TimeSetting -eq $CurrentInterval) {
        Write-Host "Executing"
        foreach ($Tenant in $TenantsToProcess | Sort-Object lastEndTime) {
            Push-OutputBinding -Name NinjaProcess -Value @{
                'NinjaAction'  = 'SyncTenant'
                'MappedTenant' = $Tenant
            }
            Start-Sleep -Seconds 1

        }

        $AddObject = @{
            PartitionKey   = 'NinjaConfig'
            RowKey         = 'NinjaLastRunTime'
            'SettingValue' = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffK")
        }
        Add-AzDataTableEntity @Table -Entity $AddObject -Force
    
        Write-LogMessage -API 'NinjaOneSync' -user 'CIPP' -message "NinjaOne Daily Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" -Sev 'Info' 

    } else {
        if ($LastRunTime -lt (Get-Date).AddMinutes(-90)) {
            $TenantsToProcess | ForEach-Object {
                if ($Null -ne $_.lastEndTime -and $_.lastEndTime -ne '') {
                    $_.lastEndTime = (Get-Date($_.lastEndTime))
                } else {
                    $_ | Add-Member -NotePropertyName lastEndTime -NotePropertyValue $Null -Force
                }
        
                if ($Null -ne $_.lastStartTime -and $_.lastStartTime -ne '') {
                    $_.lastStartTime = (Get-Date($_.lastStartTime))
                } else {
                    $_ | Add-Member -NotePropertyName lastStartTime -NotePropertyValue $Null -Force
                }
            }
            $CatchupTenants = $TenantsToProcess | where-object { (((($_.lastEndTime -eq $Null) -or ($_.lastStartTime -gt $_.lastEndTime)) -and ($_.lastStartTime -lt (Get-Date).AddMinutes(-30)))) -or ($_.lastStartTime -lt $LastRunTime) }
            foreach ($Tenant in $CatchupTenants) {
                Push-OutputBinding -Name NinjaProcess -Value @{
                    'NinjaAction'  = 'SyncTenant'
                    'MappedTenant' = $Tenant
                }
                Start-Sleep -Seconds 1
            }
            if (($CatchupTenants | Measure-Object).count -gt 0){
            Write-LogMessage -API 'NinjaOneSync' -user 'CIPP' -message "NinjaOne Synchronization Catchup Queued for $(($CatchupTenants | Measure-Object).count) Tenants" -Sev 'Info' 
            }

        }

    }
}
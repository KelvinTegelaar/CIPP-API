using namespace System.Net

param($Timer)

$Table = Get-CIPPTable -TableName Extensionsconfig

$Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json)

Write-Host 'Started Scheduler for Extensions'

# NinjaOne Extension
if ($Configuration.NinjaOne.Enabled -eq $True) {
    Invoke-NinjaOneExtensionScheduler
}
$CippRoot = (Get-Item $PSScriptRoot).Parent.FullName
### Read the local.settings.json file and convert to a PowerShell object.
$CIPPSettings = Get-Content (Join-Path $CippRoot 'local.settings.json') | ConvertFrom-Json | Select-Object -ExpandProperty Values
### Loop through the settings and set environment variables for each.
$ValidKeys = @('TenantID', 'ApplicationID', 'ApplicationSecret', 'RefreshToken', 'AzureWebJobsStorage', 'PartnerTenantAvailable', 'SetFromProfile')
foreach ($Key in $CIPPSettings.PSObject.Properties.Name) {
    if ($ValidKeys -contains $Key) {
        [Environment]::SetEnvironmentVariable($Key, $CippSettings.$Key)
    }
}

$PowerShellWorkerRoot = Join-Path $env:ProgramFiles 'Microsoft\Azure Functions Core Tools\workers\powershell\7.4\Microsoft.Azure.Functions.PowerShellWorker.dll'
if ((Test-Path $PowerShellWorkerRoot) -and !('Microsoft.Azure.Functions.PowerShellWorker' -as [type])) {
    Write-Information "Loading PowerShell Worker from $PowerShellWorkerRoot"
    Add-Type -Path $PowerShellWorkerRoot
}

Import-Module ( Join-Path $CippRoot 'Modules\AzBobbyTables' )
Import-Module ( Join-Path $CippRoot 'Modules\DNSHealth' )
Import-Module ( Join-Path $CippRoot 'Modules\CIPPCore' )
Import-Module ( Join-Path $CippRoot 'Modules\CippExtensions' )

Get-CIPPAuthentication

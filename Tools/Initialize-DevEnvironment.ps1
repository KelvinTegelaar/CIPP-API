$CippRoot = (Get-Item $PSScriptRoot).Parent.FullName
### Read the local.settings.json file and convert to a PowerShell object.
$CIPPSettings = Get-Content (Join-Path $CippRoot "local.settings.json") | ConvertFrom-Json | Select-Object -ExpandProperty Values
### Loop through the settings and set environment variables for each.
$ValidKeys = @('TenantID', 'ApplicationID', 'ApplicationSecret', 'RefreshToken', 'AzureWebJobsStorage', 'PartnerTenantAvailable', 'SetFromProfile')
ForEach ($Key in $CIPPSettings.PSObject.Properties.Name) {
    if ($ValidKeys -Contains $Key) {
        [Environment]::SetEnvironmentVariable($Key, $CippSettings.$Key)
    }
}

Import-Module ( Join-Path $CippRoot "Modules\AzBobbyTables" )
Import-Module ( Join-Path $CippRoot "Modules\DNSHealth" )
Import-Module ( Join-Path $CippRoot "Modules\CIPPCore" )
Import-Module ( Join-Path $CippRoot "Modules\CippExtensions" )

Get-CIPPAuthentication

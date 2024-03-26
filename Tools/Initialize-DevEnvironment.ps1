$CippRoot = (Get-Item $PSScriptRoot).Parent.FullName
### Read the local.settings.json file and convert to a PowerShell object.
$CIPPSettings = Get-Content "$CippRoot\local.settings.json" | ConvertFrom-Json | Select-Object -ExpandProperty Values
### Loop through the settings and set environment variables for each.
$ValidKeys = @('TenantId', 'ApplicationId', 'ApplicationSecret', 'RefreshToken', 'AzureWebJobsStorage', 'PartnerTenantAvailable', 'SetFromProfile')
ForEach ($Key in $CIPPSettings.PSObject.Properties.Name) {
    if ($ValidKeys -Contains $Key) {
        [Environment]::SetEnvironmentVariable($Key, $CippSettings.$Key)
    }
}

Import-Module "$CippRoot\Modules\AzBobbyTables"
Import-Module "$CippRoot\Modules\DNSHealth"
Import-Module "$CippRoot\Modules\CippQueue"
Import-Module "$CippRoot\Modules\CippCore"
Get-CIPPAuthentication
using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$Alerts = [System.Collections.ArrayList]@()
$Table = Get-CippTable -tablename CippAlerts
$PartitionKey = Get-Date -UFormat '%Y%m%d'
$Filter = "PartitionKey eq '{0}'" -f $PartitionKey
$Rows = Get-AzDataTableEntity @Table -Filter $Filter | Sort-Object TableTimestamp -Descending | Select-Object -First 10



Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$APIVersion = Get-Content "version_latest.txt" | Out-String
$CIPPVersion = $request.query.localversion

$RemoteAPIVersion = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/KelvinTegelaar/CIPP-API/master/version_latest.txt"
$RemoteCIPPVersion = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/KelvinTegelaar/CIPP/master/public/version_latest.txt"

$version = [PSCustomObject]@{
    LocalCIPPVersion     = $CIPPVersion
    RemoteCIPPVersion    = $RemoteCIPPVersion
    LocalCIPPAPIVersion  = $APIVersion
    RemoteCIPPAPIVersion = $RemoteAPIVersion
    OutOfDateCIPP        = ([version]$RemoteCIPPVersion -gt [version]$CIPPVersion)
    OutOfDateCIPPAPI     = ([version]$RemoteAPIVersion -gt [version]$APIVersion)
}
if ($version.outOfDateCIPP) {
    $Alerts.add(@{Alert = 'Your CIPP Frontend is out of date. Please update to the latest version. Find more on the following '; link = "https://docs.cipp.app/setup/installation/updating"; type = "warning" })
    Write-LogMessage -message "Your CIPP Frontend is out of date. Please update to the latest version" -API 'Updates' -tenant "All Tenants" -sev Alert

}
if ($version.outOfDateCIPPAPI) {
    $Alerts.add(@{Alert = 'Your CIPP API is out of date. Please update to the latest version. Find more on the following'; link = "https://docs.cipp.app/setup/installation/updating"; type = "warning" })
    Write-LogMessage -message "Your CIPP API is out of date. Please update to the latest version" -API 'Updates' -tenant "All Tenants" -sev Alert
}


if ($env:ApplicationID -eq 'LongApplicationID' -or $null -eq $ENV:ApplicationID) { $Alerts.add(@{Alert = 'You have not yet setup your SAM Setup. Please go to the SAM Wizard in settings to finish setup'; link = "/cipp/setup"; type = "warning" }) }
if ($env:FUNCTIONS_EXTENSION_VERSION -ne '~4') {
    $Alerts.add(@{Alert = 'Your Function App is running on a Runtime version lower than 4. This impacts performance. Go to Settings -> Backend -> Function App Configuration -> Function Runtime Settings and set this to 4 for maximum performance'; link = "/cipp/setup"; type = "warning" }) 
}
if ($psversiontable.psversion.toString() -lt 7.2) { $Alerts.add(@{Alert = 'Your Function App is running on Powershell 7. This impacts performance. Go to Settings -> Backend -> Function App Configuration -> General Settings and set PowerShell Core Version to 7.2 for maximum performance'; link = "/cipp/setup"; type = "danger" }) }
if ($env:WEBSITE_RUN_FROM_PACKAGE -ne '1') {
    $Alerts.add(
        @{Alert  = 'Your Function App is running in write mode. This will cause performance issues and increase cost. Please check this ';
            link = "https://docs.cipp.app/setup/installation/runfrompackage"; 
            type = "warning" 
        }) 
}
if ($Rows) { $Rows | ForEach-Object { $alerts.add($_) } }
$Alerts = @($Alerts)
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
 
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Alerts
    })

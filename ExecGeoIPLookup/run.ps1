using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
Write-Host $Request.Query.IP
$location = Get-CIPPGeoIPLocation -IP $Request.query.IP
$ARINInfo = Invoke-RestMethod -Uri "https://whois.arin.net/rest/ip/$($Request.Query.IP)" -Method Get -ContentType "application/json" -Headers @{Accept = "application/json" }
$LocationInfo = [pscustomobject]@{
    location     = $location
    arin         = $ARINInfo
    startaddress = $arininfo.net.startaddress.'$'  
    endAddress   = $arininfo.net.endAddress.'$'
    OrgRef       = $arininfo.net.orgRef.'@NAME'
    SubnetName   = $arininfo.net.name.'$'
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $LocationInfo
    })

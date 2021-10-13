using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$Skiplist = (get-content ExcludedTenants -ErrorAction SilentlyContinue | convertfrom-csv -delimiter "|" -header "name","date","user").name
# Write to the Azure Functions log stream.
$cachefile = 'tenants.cache.json'
$Testfile = get-item  $cachefile  -ErrorAction SilentlyContinue | where-object -property LastWriteTime -gt (get-date).Addhours(-24)
if($Testfile){
    write-host "using cache"
    $GraphRequest = get-content $cachefile | convertfrom-json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $GraphRequest | where-object -property DefaultdomainName -notin $Skiplist
})
exit
} else {
write-host "Grabbing all tenants via Graph API" -ForegroundColor Green
$GraphRequest = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contracts?`$top=999" -tenantid $ENV:Tenantid) | select-object CustomerID,DefaultdomainName,DisplayName,domains | where-object -property DefaultdomainName -notin $Skiplist
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $GraphRequest
})

$GraphRequest | convertto-json | out-file $cachefile
}


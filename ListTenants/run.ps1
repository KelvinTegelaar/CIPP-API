using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# We create the excluded tenants file. This is not set to force so will not overwrite
New-Item -ErrorAction SilentlyContinue -ItemType File -Path "ExcludedTenants"

# Set cache locations
$cachefile = 'tenants.cache.json'

# Clear Cache
if ($request.Query.ClearCache -eq "true") {
    Remove-Item $cachefile -Force
    Get-ChildItem -Path "Cache_BestPracticeAnalyser" -Filter *.json | Remove-Item -Force -ErrorAction SilentlyContinue
    $GraphRequest = [pscustomobject]@{"Results" = "Successfully completed request." }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $GraphRequest
        })
    exit
}

# Get the list of tenants to skip, create the file first if it does not exist yet.
$Skiplist = (Get-Content ExcludedTenants -ErrorAction SilentlyContinue | ConvertFrom-Csv -Delimiter "|" -Header "name", "date", "user").name

# Get the tenant cache file where it is under 24 hours old. If it's over 24 hours old, re-create it
$Testfile = Get-Item $cachefile -ErrorAction SilentlyContinue | Where-Object -Property LastWriteTime -GT (Get-Date).Addhours(-24)
if ($Testfile) {    
    $GraphRequest = Get-Content $cachefile | ConvertFrom-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $GraphRequest | Where-Object -Property DefaultdomainName -NotIn $Skiplist
        })
    exit
}
else {
    Write-Host "Grabbing all tenants via Graph API" -ForegroundColor Green
    $GraphRequest = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contracts?`$top=999" -tenantid $ENV:Tenantid) | Select-Object CustomerID, DefaultdomainName, DisplayName, domains | Where-Object -Property DefaultdomainName -NotIn $Skiplist
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $GraphRequest
        })
    
    # Re have returned tenants now, but we still need to generate the cache file and save it
    if ($GraphRequest) {
        $GraphRequest | ConvertTo-Json | Out-File $cachefile
    }
}

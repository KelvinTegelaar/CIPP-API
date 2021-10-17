using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$Skiplist = (Get-Content ExcludedTenants -ErrorAction SilentlyContinue | ConvertFrom-Csv -Delimiter "|" -Header "name", "date", "user").name
# Write to the Azure Functions log stream.
$cachefile = 'tenants.cache.json'
$Testfile = Get-Item  $cachefile  -ErrorAction SilentlyContinue | Where-Object -Property LastWriteTime -GT (Get-Date).Addhours(-24)
if ($Testfile) {
    if ($request.Query.ClearCache -eq "true") {
        Remove-Item $cachefile -Force 
        $GraphRequest = [pscustomobject]@{"Results" = "Successfully completed request." }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $GraphRequest
            })
    }
    else {
        $GraphRequest = Get-Content $cachefile | ConvertFrom-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $GraphRequest | Where-Object -Property DefaultdomainName -NotIn $Skiplist
            })
        exit
    }
}
else {
    Write-Host "Grabbing all tenants via Graph API" -ForegroundColor Green
    $GraphRequest = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contracts?`$top=999" -tenantid $ENV:Tenantid) | Select-Object CustomerID, DefaultdomainName, DisplayName, domains | Where-Object -Property DefaultdomainName -NotIn $Skiplist
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $GraphRequest
        })

    if ($GraphRequest) {
        $GraphRequest | ConvertTo-Json | Out-File $cachefile

    }
}


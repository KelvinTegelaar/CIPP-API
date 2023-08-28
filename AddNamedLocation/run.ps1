using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Input bindings are passed in via param block.
$Tenants = $request.body.selectedTenants.defaultDomainName
Write-Host ($Request.body | ConvertTo-Json)
if ($Tenants -eq "AllTenants") { $Tenants = (Get-Tenants).defaultDomainName }
$results = foreach ($Tenant in $tenants) {
    try {
        $ObjBody = if ($Request.body.Type -eq "IPLocation") {
            $IPRanges = ($Request.body.Ips -split "`n") | ForEach-Object { if ($_ -ne "") { @{cidrAddress = "$_" } } }
            if (!$IPRanges) { $IPRanges = @(@{cidrAddress = "$($Request.Body.Ips)" }) }
            [pscustomobject]@{
                "@odata.type" = "#microsoft.graph.ipNamedLocation"
                displayName   = $request.body.policyName
                ipRanges      = @($IPRanges)
                isTrusted     = $Request.body.Trusted
            }
        }
        else {
            [pscustomobject]@{
                "@odata.type"                     = "#microsoft.graph.countryNamedLocation"
                displayName                       = $request.body.policyName
                countriesAndRegions               = @($Request.Body.Countries.value)
                includeUnknownCountriesAndRegions = $Request.body.includeUnknownCountriesAndRegions
            }
        }
        $Body = ConvertTo-Json -InputObject $ObjBody
        $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations" -body $body -Type POST -tenantid $tenant
        "Successfully added Named Location for $($Tenant)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message " added Named Location $($Displayname)" -Sev "Info"

    }
    catch {
        "Failed to add Named Location $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Failed adding Named Location$($Displayname). Error: $($_.Exception.Message)" -Sev "Error"
        continue
    }

}

$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

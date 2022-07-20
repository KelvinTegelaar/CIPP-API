using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Get me some of that classic token!
$token = Get-ClassicAPIToken -Resource "https://admin.microsoft.com" -tenantID $Env:TenantID

# Get the list of authorised tenants so we can take into account exclusions
$Tenants = Get-Tenants

# This allows access to a tenant key that is needed in the POST for service health
$ResultClients = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri 'https://admin.microsoft.com/admin/api/partners/GetAOBOClients/true' -Method Get -Headers @{
    Authorization            = "Bearer $($token.access_token)";
    "x-ms-client-request-id" = [guid]::NewGuid().ToString();
    "x-ms-client-session-id" = [guid]::NewGuid().ToString()
    'x-ms-correlation-id'    = [guid]::NewGuid()
    'X-Requested-With'       = 'XMLHttpRequest' 
}

# Filter out the tenants that shouldn't be there
$ResultClients = $ResultClients | Where-Object { $Tenants.customerId -contains $_.TenantId }

# Build the body
$Body = $ResultClients.TenantKey | ConvertTo-Json


# Get the service health info
$ResultHealthSummary = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri 'https://admin.microsoft.com/admin/api/tenant/listservicehealthsummary' -Method POST -Body $body -Headers @{
    Authorization            = "Bearer $($token.access_token)";
    "x-ms-client-request-id" = [guid]::NewGuid().ToString();
    "x-ms-client-session-id" = [guid]::NewGuid().ToString()
    'x-ms-correlation-id'    = [guid]::NewGuid()
    'X-Requested-With'       = 'XMLHttpRequest' 
}

# Build up a better object and some stats with it. Note we are removing anything that has an end date as we only care about ongoing health alerts

$ReturnObject = foreach ($h in $ResultHealthSummary) {
    $SH = [PSCustomObject]@{
        TenantName         = $($ResultClients | Where-Object { $_.TenantID -eq $h.TenantID } | Select-Object -ExpandProperty Name)
        TenantID           = $h.TenantID
        AdvisoryCount      = $($h.HealthIssueDetails | Where-Object { ($null -eq $_.EndDateTime) -and ($_.Classification -eq 1) } | Measure-Object | Select-Object -ExpandProperty Count)
        IncidentCount      = $($h.HealthIssueDetails | Where-Object { ($null -eq $_.EndDateTime) -and ($_.Classification -eq 2) } | Measure-Object | Select-Object -ExpandProperty Count)
        HealthIssueDetails = $($h.HealthIssueDetails | Where-Object { $null -eq $_.EndDateTime })
    }
    $SH
}
$StatusCode = [HttpStatusCode]::OK

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($ReturnObject)
    })

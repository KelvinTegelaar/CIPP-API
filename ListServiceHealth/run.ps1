using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


$ResultHealthSummary = Get-Tenants | ForEach-Object -Parallel {
    Import-Module '.\GraphHelper.psm1'
    $tenantname = $_.displayName
    Write-Host $tenantname
    $prop = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/admin/serviceAnnouncement/issues?`$filter=endDateTime eq null" -tenantid $_.defaultDomainName
    $prop | Add-Member -NotePropertyName 'tenant' -NotePropertyValue $tenantname
    $prop
}
$Results = foreach ($h in $ResultHealthSummary) {
    [PSCustomObject]@{
        TenantName = $h.tenant
        issueId    = $h.ID
        service    = $h.service
        type       = $h.feature
        desc       = $h.impactDescription
    }
}

$StatusCode = [HttpStatusCode]::OK

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Results)
    })

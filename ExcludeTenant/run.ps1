using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$user = $request.headers.'x-ms-client-principal'

$username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | convertfrom-json).userDetails
$date = (get-date).tostring('dd-MM-yyyy')
try {
      if ($Request.Query.List) {
        $ExcludedTenants = [System.IO.File]::ReadAllLines("ExcludedTenants") | convertfrom-csv -delimiter "|" -header "Name","User","Date" | where-object{ $_.name -ne ""} 
        Log-Request -user $request.headers.'x-ms-client-principal'   -message "got excluded tenants list" -Sev "Info"
        $body = $ExcludedTenants
    }
    # Interact with query parameters or the body of the request.
    $name = $Request.Query.TenantFilter
    if ($Request.Query.AddExclusion) {
        Add-content -Value "$($name)|$($username)|$($date)" -path "ExcludedTenants"
        Log-Request -user $request.headers.'x-ms-client-principal'   -message "Added exclusion for customer $($name)" -Sev "Info"
        $body = [pscustomobject]@{"Results" = "Success. We've added $name to the excluded tenants." }
    }

    if ($Request.Query.RemoveExclusion) {
        $Content = [System.IO.File]::ReadAllLines("ExcludedTenants")
        $Content = $Content -replace $name, ''
        $Content | Set-Content -Path "ExcludedTenants"
        Log-Request -user $request.headers.'x-ms-client-principal'   -message "Removed exclusion for customer $($name)" -Sev "Info"
        $body = [pscustomobject]@{"Results" = "Success. We've removed $name from the excluded tenants." }
    }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Exclusion API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

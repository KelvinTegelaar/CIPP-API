using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$user = $request.headers.'x-ms-client-principal'
$username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails

try {
    $Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
    $Settings = ($request.body | Select-Object -Property * -ExcludeProperty Select_*, DataTable* )
    foreach ($Tenant in $tenants) {
        
        $object = [PSCustomObject]@{
            Tenant    = $tenant
            AddedBy   = $username
            Standards = $Settings
        } | ConvertTo-Json
        Set-Content "$($tenant).Standards.json" -Value $Object
    }
    $body = [pscustomobject]@{"Results" = "Successfully added standards deployment" }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'  -message "Standards API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to add standard: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
$DefinitionsList = ($request.body.RawJSON | ConvertFrom-Json).added
$Tenant = ($Request.body | Select-Object Select_*).psobject.properties.value | Select-Object -First 1
$Results = foreach ($DefinitionLink in $DefinitionsList) {
    try {
        $uri = $DefinitionLink.'definition@odata.bind'
        $Data = New-GraphGetRequest -uri $uri -tenantid $Tenant
        [PSCustomObject]@{
            Name  = $data.displayName
            value = $DefinitionLink.enabled
        }
    }
    catch {
        "Could not retrieve definition for $DefinitionLink"
    }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
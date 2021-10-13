using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$Tenants = get-childitem *.standards.json

$CurrentStandards = foreach ($tenant in $tenants) {
    $StandardsFile = get-content "$($tenant)" | convertfrom-json
    if($StandardsFile.Tenant -eq $null){ continue }
        [PSCustomObject]@{
            displayName  = $StandardsFile.tenant
            standardName = ($standardsFile.Standards.psobject.properties.name -join ' & ')
            appliedBy    = $StandardsFile.addedby
        }
    }


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($CurrentStandards)
    })

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$Table = Get-CIPPTable -TableName CippMapping

if ($Request.Query.List) {
    switch ($Request.Query.List) {
        'Halo' {
            $body = Get-HaloMapping -CIPPMapping $Table
        }
    }
}
try {
    if ($Request.Query.AddMapping) {
        switch ($Request.Query.AddMapping) {
            'Halo' {
                $body = Set-HaloMapping -CIPPMapping $Table -APIName $APIName -Request $Request
            }
        }
    }
} catch {
    Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "mapping API failed. $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

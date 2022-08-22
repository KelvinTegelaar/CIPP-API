using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# List of supported resolvers
$ValidResolvers = @(
    'Google'
    'Cloudflare'
    'Quad9'
)

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$StatusCode = [HttpStatusCode]::OK
try {
    $ConfigTable = Get-CippTable -tablename Config
    $Filter = "PartitionKey eq 'Domains' and RowKey eq 'Domains'"
    $Config = Get-AzDataTableEntity @ConfigTable -Filter $Filter

    if ($ValidResolvers -notcontains $Config.Resolver) {
        $Config = @{
            PartitionKey = 'Domains'
            RowKey       = 'Domains'
            Resolver     = 'Google'
        }
        Add-AzDataTableEntity @ConfigTable -Entity $Config -Force
    }

    $updated = $false

    # Interact with query parameters or the body of the request.
    if ($Request.Query.Action -eq 'SetConfig') {
        if ($Request.Query.Resolver) {
            $Resolver = $Request.Query.Resolver
            if ($ValidResolvers -contains $Resolver) {
                try {
                    $Config.Resolver = $Resolver
                }
                catch {
                    $Config = @{
                        Resolver = $Resolver
                    }
                }
                $updated = $true
            }
        }
        if ($updated) {
            Add-AzDataTableEntity @ConfigTable -Entity $Config -Force
            Write-LogMessage -API $APINAME -tenant 'Global' -user $request.headers.'x-ms-client-principal' -message 'DNS configuration updated' -Sev 'Info' 
            $body = [pscustomobject]@{'Results' = 'Success: DNS configuration updated.' }
        }
        else {
            $StatusCode = [HttpStatusCode]::BadRequest
            $body = [pscustomobject]@{'Results' = 'Error: No DNS resolver provided.' }
        }
    }
    elseif ($Request.Query.Action -eq 'GetConfig') {
        $body = [pscustomobject]$Config
        Write-LogMessage -API $APINAME -tenant 'Global' -user $request.headers.'x-ms-client-principal' -message 'Retrieved DNS configuration' -Sev 'Info' 
    }
}
catch {
    Write-LogMessage -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal' -message "DNS Config API failed. $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    $StatusCode = [HttpStatusCode]::BadRequest
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $body
    })

using namespace System.Net

Function Invoke-ListPendingWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    try {
        $Table = Get-CIPPTable -TableName 'WebhookIncoming'
        $Webhooks = Get-CIPPAzDataTableEntity @Table
        $Results = $Webhooks | Select-Object -ExcludeProperty RowKey, PartitionKey, ETag, Timestamp
        $PendingWebhooks = foreach ($Result in $Results) {
            foreach ($Property in $Result.PSObject.Properties.Name) {
                if (Test-Json -Json $Result.$Property -ErrorAction SilentlyContinue) {
                    $Result.$Property = $Result.$Property | ConvertFrom-Json
                }
            }
            $Result
        }
    } catch {
        $PendingWebhooks = @()
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($PendingWebhooks)
                Metadata = @{
                    Count = ($PendingWebhooks | Measure-Object).Count
                }
            }
        })
}

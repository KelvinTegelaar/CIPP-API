using namespace System.Net

Function Invoke-ListWebhookAlert {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Table = get-cipptable -TableName 'SchedulerConfig'
    $WebhookRow = Get-CIPPAzDataTableEntity @Table | Where-Object -Property PartitionKey -EQ 'WebhookAlert' 
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($WebhookRow)
        })


}

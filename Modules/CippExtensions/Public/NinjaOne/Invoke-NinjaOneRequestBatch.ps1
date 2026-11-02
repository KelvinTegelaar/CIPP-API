function Invoke-NinjaOneRequestBatch {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Sends NinjaOne API requests concurrently over the pooled client and returns one result per request, in input order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)]$Token,
        # Each item: @{ Method = 'PATCH'; Path = '/api/v2/...'; Body = '<json>' }
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Requests,
        [int]$Concurrency = 8,
        [int]$MaxRetries = 3,
        [int]$TimeoutSec = 300
    )

    if ($Requests.Count -eq 0) { return }
    $Batch = foreach ($Request in $Requests) {
        $Item = [CIPP.CIPPConcurrentRequest]::new()
        $Item.Uri = "https://$($Configuration.Instance)$($Request.Path)"
        $Item.Method = $Request.Method
        $Item.Body = $Request.Body
        $Item.ContentType = 'application/json; charset=utf-8'
        $Item.TimeoutSec = $TimeoutSec
        $Item.Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $Item.Headers['Authorization'] = "Bearer $($Token.access_token)"
        $Item
    }
    [CIPP.CIPPRestClient]::SendConcurrent([CIPP.CIPPConcurrentRequest[]]@($Batch), $Concurrency, $MaxRetries)
}

using namespace System.Net

Function Invoke-ExecAddTrustedIP {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'trustedIps'
    Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey = $request.query.tenantfilter
        RowKey       = $Request.query.ip
        state        = $request.query.State
    } -Force

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ results = "Added $($Request.query.ip) to database with state $($Request.query.state) for $($Request.query.tenantfilter)" }
        })
}
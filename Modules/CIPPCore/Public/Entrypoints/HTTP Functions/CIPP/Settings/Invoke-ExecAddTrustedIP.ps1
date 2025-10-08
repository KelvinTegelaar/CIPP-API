function Invoke-ExecAddTrustedIP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'trustedIps'
    foreach ($IP in $Request.body.IP) {
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = $Request.Body.tenantfilter
            RowKey       = $IP
            state        = $Request.Body.State
        } -Force
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ results = "Added $($Request.Body.IP) to database with state $($Request.Body.State) for $($Request.Body.tenantfilter)" }
        })
}

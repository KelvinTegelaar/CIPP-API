using namespace System.Net

Function Invoke-ExecAddTrustedIP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'trustedIps'
    Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey = $Request.Body.tenantfilter
        RowKey       = $Request.Body.IP
        state        = $Request.Body.State
    } -Force

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ results = "Added $($Request.Body.IP) to database with state $($Request.Body.State) for $($Request.Body.tenantfilter)" }
        })
}

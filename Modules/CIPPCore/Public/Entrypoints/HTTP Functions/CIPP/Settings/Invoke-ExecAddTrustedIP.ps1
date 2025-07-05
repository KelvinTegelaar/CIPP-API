using namespace System.Net

function Invoke-ExecAddTrustedIP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CippTable -tablename 'trustedIps'
    Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey = $Request.Body.tenantFilter
        RowKey       = $Request.Body.IP
        state        = $Request.Body.State
    } -Force

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ results = "Added $($Request.Body.IP) to database with state $($Request.Body.State) for $($Request.Body.tenantFilter)" }
    }
}

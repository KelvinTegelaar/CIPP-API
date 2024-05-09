function Get-CIPPAlertVppTokenExpiry {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )
    $LastRunTable = Get-CIPPTable -Table AlertLastRun


    try {
        $Filter = "RowKey eq 'VppTokenExpiry' and PartitionKey eq '{0}'" -f $TenantFilter
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            try {
                $VppTokens = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/vppTokens' -tenantid $TenantFilter).value
                foreach ($Vpp in $VppTokens) {
                    if ($Vpp.state -ne 'valid') {
                        Write-AlertMessage -tenant $($TenantFilter) -message 'Apple Volume Purchase Program Token is not valid, new token required'
                    }
                    if ($Vpp.expirationDateTime -lt (Get-Date).AddDays(30) -and $Vpp.expirationDateTime -gt (Get-Date).AddDays(-7)) {
                        Write-AlertMessage -tenant $($TenantFilter) -message ('Apple Volume Purchase Program token expiring on {0}' -f $Vpp.expirationDateTime)
                    }
                }
            } catch {}
            $LastRun = @{
                RowKey       = 'VppTokenExpiry'
                PartitionKey = $TenantFilter
            }
            Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
        }
    } catch {
        # Error handling
    }
}
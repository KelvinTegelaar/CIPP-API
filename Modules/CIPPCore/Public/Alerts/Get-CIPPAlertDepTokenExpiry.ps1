function Get-CIPPAlertDepTokenExpiry {
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
        $Filter = "RowKey eq 'DepTokenExpiry' and PartitionKey eq '{0}'" -f $TenantFilter
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            try {
                $DepTokens = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $TenantFilter).value
                foreach ($Dep in $DepTokens) {
                    if ($Dep.tokenExpirationDateTime -lt (Get-Date).AddDays(30) -and $Dep.tokenExpirationDateTime -gt (Get-Date).AddDays(-7)) {
                        Write-AlertMessage -tenant $($TenantFilter) -message ('Apple Device Enrollment Program token expiring on {0}' -f $Dep.tokenExpirationDateTime)
                    }
                }
            } catch {}
            $LastRun = @{
                RowKey       = 'DepTokenExpiry'
                PartitionKey = $TenantFilter
            }
            Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
        }
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check Apple Device Enrollment Program token expiry for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

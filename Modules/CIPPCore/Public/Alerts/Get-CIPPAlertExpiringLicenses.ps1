function Get-CIPPAlertExpiringLicenses {
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
    try {
        Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {
            $timeTorenew = [int64]$_.TimeUntilRenew
            if ($timeTorenew -lt 30 -and $_.TimeUntilRenew -gt 0) {
                Write-Host "$($_.License) will expire in $($_.TimeUntilRenew) days. The estimated term is $($_.EstTerm)"
                Write-AlertMessage -tenant $($TenantFilter) -message "$($_.License) will expire in $($_.TimeUntilRenew) days. The estimated term is $($_.EstTerm)"
            }
        }
    } catch {
    }
}


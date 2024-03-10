function Push-CIPPAlertExpiringLicenses {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )
    try {
        Get-CIPPLicenseOverview -TenantFilter $Item.tenant | ForEach-Object {
            $timeTorenew = [int64]$_.TimeUntilRenew
            if ($timeTorenew -lt 30 -and $_.TimeUntilRenew -gt 0) {
                Write-Host "$($_.License) will expire in $($_.TimeUntilRenew) days. The estimated term is $($_.EstTerm)"
                Write-AlertMessage -tenant $($Item.tenant) -message "$($_.License) will expire in $($_.TimeUntilRenew) days. The estimated term is $($_.EstTerm)"
            }
        }
    } catch {
    }
}


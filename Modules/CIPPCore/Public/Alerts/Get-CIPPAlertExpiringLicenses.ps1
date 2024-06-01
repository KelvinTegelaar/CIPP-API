function Get-CIPPAlertExpiringLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $AlertData = Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {
            $timeTorenew = [int64]$_.TimeUntilRenew
            if ($timeTorenew -lt 30 -and $_.TimeUntilRenew -gt 0) {
                Write-Host "$($_.License) will expire in $($_.TimeUntilRenew) days. The estimated term is $($_.EstTerm)"
                "$($_.License) will expire in $($_.TimeUntilRenew) days. The estimated term is $($_.EstTerm)"
            }

        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
    }
}


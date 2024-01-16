function Push-CIPPAlertExpiringLicenses {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    try {
        Get-CIPPLicenseOverview -TenantFilter $QueueItem.tenant | ForEach-Object {
            $timeTorenew = [int64]$_.TimeUntilRenew
            if ($timeTorenew -lt 30 -and $_.TimeUntilRenew -gt 0) {
                Write-Host "$($_.License) will expire in $($_.TimeUntilRenew) days. The estimated term is $($_.EstTerm)"
                Write-AlertMessage -tenant $($QueueItem.tenant) -message "$($_.License) will expire in $($_.TimeUntilRenew) days. The estimated term is $($_.EstTerm)"
            }
        }
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
    }
}


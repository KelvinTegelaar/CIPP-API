function Get-CIPPAlertQuotaUsed {
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
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $TenantFilter | ForEach-Object {
            if ($_.StorageUsedInBytes -eq 0) { continue }
            $PercentLeft = [math]::round($_.StorageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes * 100)
            if ($Item.value -eq $true) {
                if ($Input) { $Value = $input } else { $Value = 90 }
                if ($PercentLeft -gt 90) {
                    Write-AlertMessage -tenant $($TenantFilter) -message "$($_.UserPrincipalName): Mailbox is more than $($value)% full. Mailbox is $PercentLeft% full"
                }
            }
        }
    } catch {
    }
}

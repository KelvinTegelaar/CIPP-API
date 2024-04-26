function Push-CIPPAlertQuotaUsed {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )


    try {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $Item.tenant | ForEach-Object {
            if ($_.StorageUsedInBytes -eq 0) { continue }
            $PercentLeft = [math]::round($_.StorageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes * 100)
            if ($Item.value -eq $true) {
                if ($Item.value) { $Value = $Item.value } else { $Value = 90 }
                if ($PercentLeft -gt 90) {
                    Write-AlertMessage -tenant $($Item.tenant) -message "$($_.UserPrincipalName): Mailbox is more than $($value)% full. Mailbox is $PercentLeft% full"
                }
            }
        }
    } catch {
    }
}

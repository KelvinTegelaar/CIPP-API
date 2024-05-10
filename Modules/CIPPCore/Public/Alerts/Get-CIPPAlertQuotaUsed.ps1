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
        $AlertData = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $TenantFilter | ForEach-Object {
            if ($_.StorageUsedInBytes -eq 0) { return }
            $PercentLeft = [math]::round($_.StorageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes * 100)
            if ($Input) { $Value = $input } else { $Value = 90 }
            if ($PercentLeft -gt $Value) {
                "$($_.UserPrincipalName): Mailbox is more than $($value)% full. Mailbox is $PercentLeft% full"
            }
            
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
    }
}

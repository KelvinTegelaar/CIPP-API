function Get-CIPPAlertQuotaUsed {
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
        $AlertData = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $TenantFilter
    } catch {
        return
    }
    $OverQuota = $AlertData | ForEach-Object {
        if ([string]::IsNullOrEmpty($_.StorageUsedInBytes) -or [string]::IsNullOrEmpty($_.prohibitSendReceiveQuotaInBytes) -or $_.StorageUsedInBytes -eq 0 -or $_.prohibitSendReceiveQuotaInBytes -eq 0) { return }
        try {
            $PercentLeft = [math]::round(($_.storageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes) * 100)
        } catch { $PercentLeft = 100 }
        try {
            if ([int]$InputValue -gt 0) {
                $Value = [int]$InputValue
            } else {
                $Value = 90
            }
        } catch {
            $Value = 90
        }
        if ($PercentLeft -gt $Value) {
            "$($_.userPrincipalName): Mailbox is more than $($value)% full. Mailbox is $PercentLeft% full"
        }

    }
    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $OverQuota
}

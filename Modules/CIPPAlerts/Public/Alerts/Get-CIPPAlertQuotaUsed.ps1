function Get-CIPPAlertQuotaUsed {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        [Parameter(Mandatory)]
        $TenantFilter
    )

    $Threshold = if ($InputValue.QuotaUsedQuota) { [int]$InputValue.QuotaUsedQuota } else { 90 }
    $ExcludedRaw = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text ([string]$InputValue.QuotaUsedExcludedMailboxes)
    $Excluded = @($ExcludedRaw -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })

    try {
        $AlertData = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json&`$top=999" -tenantid $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Mailbox quota Alert: Unable to get mailbox usage: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $OverQuota = $AlertData | ForEach-Object {
        if (!$_.StorageUsedInBytes -or !$_.prohibitSendReceiveQuotaInBytes) { return }
        if ($Excluded -contains $_.userPrincipalName.ToLower()) { return }
        $UsagePercent = [math]::Round(($_.storageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes) * 100)
        if ($UsagePercent -gt $Threshold) {
            [PSCustomObject]@{
                Message                         = "$($_.userPrincipalName): Mailbox is more than $($Threshold)% full. Mailbox is $UsagePercent% full"
                Owner                           = $_.userPrincipalName
                RecipientType                   = $_.recipientType
                UsagePercent                    = $UsagePercent
                StorageUsedInBytes              = $_.storageUsedInBytes
                ProhibitSendReceiveQuotaInBytes = $_.prohibitSendReceiveQuotaInBytes
                Tenant                          = $TenantFilter
            }
        }
    }
    if ($OverQuota) {
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $OverQuota
    }
}

function Get-CIPPAlertArchiveQuota {
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

    $Threshold = if ($InputValue.ArchiveQuotaThreshold) { [int]$InputValue.ArchiveQuotaThreshold } else { 90 }
    $ExcludedRaw = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text ([string]$InputValue.ArchiveQuotaExcludedMailboxes)
    $Excluded = @($ExcludedRaw -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })

    # Prefer the reporting DB: Set-CIPPDBCacheMailboxes already stores archive size and quota (both in
    # bytes) per mailbox, so a warm cache answers this without any Exchange Online call. The archive
    # figures change slowly and this alert runs weekly, so day-old cache data is well within tolerance.
    # Fall back to live Exchange only when the tenant has no cached mailbox data (or a cache written
    # before ArchiveQuota was added), so the alert never silently no-ops.
    $ArchiveUsage = $null
    try {
        $Cached = @(Get-CIPPMailboxesReport -TenantFilter $TenantFilter -ErrorAction Stop)
    } catch {
        $Cached = @()
    }
    $CacheHasQuota = $Cached.Count -gt 0 -and ($Cached[0].PSObject.Properties.Name -contains 'ArchiveQuota')

    if ($CacheHasQuota) {
        $ArchiveUsage = foreach ($Mailbox in $Cached) {
            if ($Mailbox.ArchiveEnabled -ne $true -or -not $Mailbox.UPN) { continue }
            [PSCustomObject]@{
                UPN           = $Mailbox.UPN
                RecipientType = $Mailbox.recipientTypeDetails
                UsedBytes     = [int64]($Mailbox.ArchiveSize ?? 0)
                QuotaBytes    = [int64]($Mailbox.ArchiveQuota ?? 0)
            }
        }
    } else {
        try {
            # -Archive limits the result to mailboxes that actually have an online archive, and the
            # quota fields ride along so only the per-mailbox usage needs a second lookup.
            $ArchiveMailboxes = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ Archive = $true } -Select 'UserPrincipalName,RecipientTypeDetails,ArchiveQuota,ArchiveGuid' -useSystemMailbox $true | Where-Object { $_.UserPrincipalName })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Archive quota Alert: Unable to get archive mailboxes: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            return
        }
        if ($ArchiveMailboxes.Count -eq 0) { return }

        # Archive size only comes from Get-MailboxStatistics. Batch it with an operation guid per
        # mailbox so each result maps back to its mailbox, the same pattern the reporting-DB cache uses.
        $MailboxByRequestId = @{}
        $StatsRequests = @(foreach ($Mailbox in $ArchiveMailboxes) {
                $OperationGuid = [Guid]::NewGuid().ToString()
                $MailboxByRequestId[$OperationGuid] = $Mailbox
                @{
                    CmdletInput   = @{
                        CmdletName = 'Get-MailboxStatistics'
                        Parameters = @{ Identity = $Mailbox.UserPrincipalName; Archive = $true }
                    }
                    OperationGuid = $OperationGuid
                }
            })

        try {
            $StatsResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $StatsRequests -useSystemMailbox $true
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Archive quota Alert: Unable to get archive statistics: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            return
        }

        $ArchiveUsage = foreach ($Stat in @($StatsResults)) {
            if (-not $Stat.OperationGuid -or -not $MailboxByRequestId.ContainsKey($Stat.OperationGuid) -or $Stat.error) { continue }
            $Mailbox = $MailboxByRequestId[$Stat.OperationGuid]
            [PSCustomObject]@{
                UPN           = $Mailbox.UserPrincipalName
                RecipientType = $Mailbox.RecipientTypeDetails
                UsedBytes     = Get-ExoOnlineStringBytes -SizeString ([string]$Stat.TotalItemSize)
                QuotaBytes    = Get-ExoOnlineStringBytes -SizeString ([string]$Mailbox.ArchiveQuota)
            }
        }
    }

    $OverQuota = foreach ($Item in @($ArchiveUsage)) {
        if (-not $Item.UPN) { continue }
        if ($Excluded -contains $Item.UPN.ToLower()) { continue }
        # An archive with no quota reports 0 bytes here (e.g. 'Unlimited'); skip rather than divide by zero.
        if ($Item.QuotaBytes -le 0) { continue }
        $UsagePercent = [math]::Round(($Item.UsedBytes / $Item.QuotaBytes) * 100)
        if ($UsagePercent -ge $Threshold) {
            [PSCustomObject]@{
                Message           = "$($Item.UPN): Online archive is more than $($Threshold)% full. Archive is $UsagePercent% full"
                Owner             = $Item.UPN
                RecipientType     = $Item.RecipientType
                UsagePercent      = $UsagePercent
                ArchiveUsedBytes  = $Item.UsedBytes
                ArchiveQuotaBytes = $Item.QuotaBytes
                Tenant            = $TenantFilter
            }
        }
    }

    if ($OverQuota) {
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $OverQuota
    }
}

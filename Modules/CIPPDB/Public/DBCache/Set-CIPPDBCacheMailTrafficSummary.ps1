function Set-CIPPDBCacheMailTrafficSummary {
    <#
    .SYNOPSIS
        Caches Exchange Online mail traffic summary (top senders and recipients by message volume)

    .DESCRIPTION
        Runs Get-MailTrafficSummaryReport for the TopMailSender and TopMailRecipient categories over a
        30-day window and stores one row per address as { category, name, count, windowDays } under the
        MailTrafficSummary type. This is the same data the live Mail Flow Statistics page reads, cached so
        a scheduled or pre-built report (mailboxes by messaging volume) can use it without a live EXO call.

    .PARAMETER TenantFilter
        The tenant to cache mail traffic summary for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mail traffic summary' -sev Debug

        $WindowDays = 30
        $StartDate = (Get-Date).AddDays(-$WindowDays).ToUniversalTime().ToString('s')
        $EndDate = (Get-Date).ToUniversalTime().ToString('s')

        # Both categories in one EXO batch; OperationGuid tags each returned row with the category it
        # came from (the report rows do not otherwise say). C1 is the address/name, C2 the message count.
        $Batch = @('TopMailSender', 'TopMailRecipient') | ForEach-Object {
            @{
                CmdletInput   = @{ CmdletName = 'Get-MailTrafficSummaryReport'; Parameters = @{ Category = $_; StartDate = $StartDate; EndDate = $EndDate } }
                OperationGuid = $_
            }
        }
        $Summary = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Batch) -useSystemMailbox $true

        $Rows = @(foreach ($Entry in @($Summary)) {
                if ($Entry.error -or [string]::IsNullOrWhiteSpace("$($Entry.C1)")) { continue }
                [PSCustomObject]@{
                    category   = "$($Entry.OperationGuid)"
                    name       = "$($Entry.C1)"
                    count      = [int]($Entry.C2)
                    windowDays = $WindowDays
                }
            })

        if ($Rows.Count -gt 0) {
            $Rows | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailTrafficSummary' -AddCount
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached mail traffic summary successfully ($($Rows.Count) rows)" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mail traffic summary: $($_.Exception.Message)" -sev Error
    }
}

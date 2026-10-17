function Set-CIPPDBCacheMailboxMessageConfiguration {
    <#
    .SYNOPSIS
        Caches the default compose font of every user and shared mailbox

    .DESCRIPTION
        One Get-MailboxMessageConfiguration per mailbox in the Mailboxes cache, batched 10 per
        $batch and fanned out 8 wide. A mailbox whose read failed is cached with its error so a
        consumer can tell unreadable from compliant. On demand only: not in a scheduled
        collection group.

    .PARAMETER TenantFilter
        The tenant to cache mailbox message configuration for

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
        $ReadMailboxes = {
            @((New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes').Where({
                        $_.UPN -and -not $_.WhenSoftDeleted -and $_.recipientTypeDetails -in @('UserMailbox', 'SharedMailbox')
                    }))
        }
        $Mailboxes = & $ReadMailboxes
        if ($Mailboxes.Count -eq 0) {
            Set-CIPPDBCacheMailboxes -TenantFilter $TenantFilter -Types 'None'
            $Mailboxes = & $ReadMailboxes
        }

        $Requests = foreach ($Mailbox in $Mailboxes) {
            @{
                CmdletInput   = @{ CmdletName = 'Get-MailboxMessageConfiguration'; Parameters = @{ Identity = "$($Mailbox.UPN)" } }
                OperationGuid = "$($Mailbox.UPN)"
            }
        }
        # 32 batches in flight measured fastest for a tenant; CIPPRateLimiter paces EXO to its Rate-Limit budget.
        $ById = @{}
        if ($Mailboxes.Count -gt 0) {
            foreach ($Config in @(New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Requests) -Select 'Identity,DefaultFontName,DefaultFontSize,DefaultFontColor' -MaxConcurrency 32)) {
                if ($Config.OperationGuid) { $ById["$($Config.OperationGuid)"] = $Config }
            }
        }

        $Rows = foreach ($Mailbox in $Mailboxes) {
            $UPN = "$($Mailbox.UPN)"
            $Config = $ById[$UPN]
            [PSCustomObject]@{
                id               = $UPN
                DefaultFontName  = $Config.DefaultFontName
                DefaultFontSize  = $Config.DefaultFontSize
                DefaultFontColor = $Config.DefaultFontColor
                error            = if (-not $Config) { 'no response' } elseif ($Config.error) { "$($Config.error)" } else { $null }
            }
        }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxMessageConfiguration' -Data @($Rows) -AddCount -ClearOnEmpty
        $Rows = $null
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mailbox message configuration: $($_.Exception.Message)" -sev Error
    }
}

function Set-CIPPDBCacheExoMailboxPlans {
    <#
    .SYNOPSIS
        Caches Exchange Online Mailbox Plans

    .DESCRIPTION
        Caches Get-MailboxPlan output with MaxSendSize/MaxReceiveSize normalized to integer MB
        so baseline compares are numeric. Exchange returns sizes as strings like
        '35 MB (36,700,160 bytes)' or 'Unlimited'; the same parsing the old
        SendReceiveLimitTenant standard used extracts the byte count, which is then rounded
        to whole MB. 'Unlimited' normalizes to $null.

    .PARAMETER TenantFilter
        The tenant to cache mailbox plans for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Mailbox Plans' -sev Debug

        $MailboxPlans = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxPlan' -cmdParams @{ ResultSize = 'Unlimited' }

        # Same extraction as the old SendReceiveLimitTenant standard: pull the byte count out of
        # the '... (n bytes)' suffix, then normalize to whole MB. 'Unlimited' becomes $null.
        $ConvertSizeToMB = {
            param($SizeString)
            if ([string]::IsNullOrWhiteSpace($SizeString) -or $SizeString -match 'Unlimited') {
                return $null
            }
            try {
                $Bytes = [int64]($SizeString -replace '.*\(([\d,]+).*', '$1' -replace ',', '')
                return [int][math]::Round($Bytes / 1MB)
            } catch {
                return $null
            }
        }

        $Plans = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($Plan in @($MailboxPlans)) {
            $Plans.Add([PSCustomObject]@{
                    Guid                    = $Plan.Guid
                    DisplayName             = $Plan.DisplayName
                    MaxRecipientsPerMessage = $Plan.MaxRecipientsPerMessage
                    MaxSendSize             = & $ConvertSizeToMB $Plan.MaxSendSize
                    MaxReceiveSize          = & $ConvertSizeToMB $Plan.MaxReceiveSize
                })
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoMailboxPlans' -Data @($Plans) -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Plans.Count) Mailbox Plans" -sev Debug
        $MailboxPlans = $null
        $Plans = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Mailbox Plans: $($_.Exception.Message)" -sev Error
    }
}

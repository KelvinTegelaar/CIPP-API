# Pester tests for Get-CIPPAlertQuotaUsed.
# The mailbox usage report's storageUsedInBytes already equals the live Get-MailboxStatistics
# TotalItemSize (it excludes the Recoverable Items dumpster and the archive), so the alert trusts the
# report figure directly. It must still skip rows the report has flagged deleted, and honour the
# threshold, exclusion and mailbox-type filters.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertQuotaUsed.ps1'

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }
    function Get-CippException { param($Exception) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }

    . $AlertPath
}

Describe 'Get-CIPPAlertQuotaUsed' {
    BeforeEach {
        # 90 GB of 100 GB according to the report.
        $script:ReportRows = @(
            [pscustomobject]@{
                userPrincipalName               = 'user@contoso.com'
                recipientType                   = 'UserMailbox'
                storageUsedInBytes              = 96636764160
                prohibitSendReceiveQuotaInBytes = 107374182400
                isDeleted                       = 'False'
            }
        )
        $script:CapturedAlertData = $null

        Mock New-GraphGetRequest { $script:ReportRows }
        Mock Get-CIPPTextReplacement { '' }
        Mock Write-LogMessage {}
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedAlertData = @($data)
        }
    }

    It 'alerts on the report figure when a mailbox is over the threshold' {
        Get-CIPPAlertQuotaUsed -InputValue @{ QuotaUsedQuota = 90 } -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Write-AlertTrace -Times 1 -Exactly
        $script:CapturedAlertData.Count | Should -Be 1
        $Row = $script:CapturedAlertData[0]
        $Row.Message | Should -Be 'user@contoso.com: Mailbox is more than 90% full. Mailbox is 90% full'
        $Row.Owner | Should -Be 'user@contoso.com'
        $Row.UsagePercent | Should -Be 90
        $Row.StorageUsedInBytes | Should -Be 96636764160
        $Row.ProhibitSendReceiveQuotaInBytes | Should -Be 107374182400
    }

    It 'does not alert when the mailbox is under the threshold' {
        $script:ReportRows[0].storageUsedInBytes = 53687091200 # 50%

        Get-CIPPAlertQuotaUsed -InputValue @{ QuotaUsedQuota = 90 } -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Write-AlertTrace -Times 0 -Exactly
    }

    It 'skips mailboxes the report has marked as deleted' {
        $script:ReportRows[0].isDeleted = 'True'

        Get-CIPPAlertQuotaUsed -InputValue @{ QuotaUsedQuota = 90 } -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Write-AlertTrace -Times 0 -Exactly
    }

    It 'only alerts on the selected mailbox types' {
        Get-CIPPAlertQuotaUsed -InputValue @{ QuotaUsedQuota = 90; QuotaUsedMailboxTypes = @{ value = @('Shared') } } -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Write-AlertTrace -Times 0 -Exactly
    }
}

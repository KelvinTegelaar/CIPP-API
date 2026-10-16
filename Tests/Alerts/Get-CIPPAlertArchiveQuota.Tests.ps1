# Archive quota alert: auto-expanding archives are skipped (the quota is not a ceiling), and a
# near-full normal archive keeps a stable hash while its usage % moves.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPMailboxesReport { param($TenantFilter) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $useSystemMailbox) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox) }
    function Get-ExoOnlineStringBytes { param($SizeString) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }
    function Get-CippException { param($Exception) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AlertContentHash.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPAutoExpandingArchiveState.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertArchiveQuota.ps1')
}

Describe 'Get-CIPPAlertArchiveQuota' {
    BeforeEach {
        $script:Captured = $null
        $script:UsedBytes = 113162000000 # ~105.4 GiB
        $script:Rows = @(
            [pscustomobject]@{ UPN = 'aea@contoso.com'; ArchiveEnabled = $true; recipientTypeDetails = 'UserMailbox'; ArchiveSize = 113162000000; ArchiveQuota = 118111600640; AutoExpandingArchive = $true }
            [pscustomobject]@{ UPN = 'plain@contoso.com'; ArchiveEnabled = $true; recipientTypeDetails = 'UserMailbox'; ArchiveSize = $script:UsedBytes; ArchiveQuota = 118111600640; AutoExpandingArchive = $false }
        )
        Mock Get-CIPPMailboxesReport { $script:Rows }
        Mock Get-CIPPTextReplacement { '' }
        Mock Write-LogMessage {}
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:Captured = @($data | Where-Object { $null -ne $_ })
        }
    }

    It 'skips auto-expanding archives and still alerts on a normal near-full archive' {
        Get-CIPPAlertArchiveQuota -InputValue @{} -TenantFilter 'contoso.onmicrosoft.com'

        $script:Captured.Count | Should -Be 1
        $script:Captured[0].Owner | Should -Be 'plain@contoso.com'
    }

    It 'keeps the item hash stable as archive usage moves' {
        Get-CIPPAlertArchiveQuota -InputValue @{} -TenantFilter 'contoso.onmicrosoft.com'
        $A = (Get-AlertContentHash -AlertItem $script:Captured[0]).ContentHash
        $script:Rows[1].ArchiveSize = 115000000000
        Get-CIPPAlertArchiveQuota -InputValue @{} -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured[0].UsagePercent | Should -Not -Be 96
        (Get-AlertContentHash -AlertItem $script:Captured[0]).ContentHash | Should -Be $A
    }

    It 'skips mailbox-level auto-expansion on the live path even when the org setting is off' {
        Mock Get-CIPPMailboxesReport { @() }
        Mock New-ExoRequest {
            @(
                [pscustomobject]@{ UserPrincipalName = 'aea@contoso.com'; RecipientTypeDetails = 'UserMailbox'; ArchiveQuota = '110 GB (118,111,600,640 bytes)'; AutoExpandingArchiveEnabled = $true }
                [pscustomobject]@{ UserPrincipalName = 'plain@contoso.com'; RecipientTypeDetails = 'UserMailbox'; ArchiveQuota = '110 GB (118,111,600,640 bytes)'; AutoExpandingArchiveEnabled = $false }
            )
        } -ParameterFilter { $cmdlet -eq 'Get-Mailbox' }
        Mock New-ExoRequest { [pscustomobject]@{ AutoExpandingArchiveEnabled = $false } }
        Mock New-ExoBulkRequest {
            @($cmdletArray | ForEach-Object { [pscustomobject]@{ OperationGuid = $_.OperationGuid; TotalItemSize = 'x' } })
        }
        Mock Get-ExoOnlineStringBytes { if ($SizeString -eq 'x') { 113162000000 } else { 118111600640 } }

        Get-CIPPAlertArchiveQuota -InputValue @{} -TenantFilter 'contoso.onmicrosoft.com'

        $script:Captured.Count | Should -Be 1
        $script:Captured[0].Owner | Should -Be 'plain@contoso.com'
        Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter { @($cmdletArray).Count -eq 1 }
    }

    It 'skips every archive when the org-level setting is on' {
        Mock Get-CIPPMailboxesReport { @() }
        Mock New-ExoRequest {
            @([pscustomobject]@{ UserPrincipalName = 'plain@contoso.com'; RecipientTypeDetails = 'UserMailbox'; ArchiveQuota = '110 GB'; AutoExpandingArchiveEnabled = $false })
        } -ParameterFilter { $cmdlet -eq 'Get-Mailbox' }
        Mock New-ExoRequest { [pscustomobject]@{ AutoExpandingArchiveEnabled = $true } }

        Get-CIPPAlertArchiveQuota -InputValue @{} -TenantFilter 'contoso.onmicrosoft.com'

        $script:Captured.Count | Should -Be 0
        Should -Invoke Write-AlertTrace -Times 1 -Exactly
    }
}

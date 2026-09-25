BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $anchor, $useSystemMailbox, $Compliance, $Select, $AsApp) }
    function Set-CIPPMailboxRule { param($Username, $UserId, $TenantFilter, $RuleId, $RuleName, [switch]$Disable, [switch]$Enable, $APIName, $Headers) }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Disable-CIPPInboxRules.ps1')
}

Describe 'Disable-CIPPInboxRules' {
    BeforeEach {
        Mock New-ExoRequest {
            @(
                [pscustomobject]@{ Name = 'Hide invoices'; Identity = 'victim\1'; Enabled = $true }
                [pscustomobject]@{ Name = 'Junk E-Mail Rule'; Identity = 'victim\junk'; Enabled = $true }
                [pscustomobject]@{ Name = 'Delegate Rule -1'; Identity = 'victim\d1'; Enabled = $true }
                [pscustomobject]@{ Name = 'Forward all'; Identity = 'victim\2'; Enabled = $true }
            )
        }
        # the real helper returns its log text; the disable function must not let that leak into its rows
        Mock Set-CIPPMailboxRule { if ($RuleName -match '^Delegate Rule') { throw 'Cannot modify delegate rule' }; "Successfully set mailbox rule $RuleName for $Username to Disabled" }
        Mock Write-LogMessage { }
    }

    It 'returns only typed result rows (no leaked helper output), skipping system and delegate rules' {
        $Rows = @(Disable-CIPPInboxRules -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com')
        $Rows | ForEach-Object { $_ | Should -BeOfType [pscustomobject] -Because 'a leaked string becomes a blank row in the containment results' }
        $Rows.Count | Should -Be 2
        ($Rows | Where-Object { $_.state -eq 'success' }).resultText | Should -Be 'Disabled 2 inbox rule(s) for victim@contoso.com.'
        ($Rows | Where-Object { $_.state -eq 'info' }).resultText | Should -Match 'Skipped 1 Exchange-managed delegate rule'
        Should -Invoke Set-CIPPMailboxRule -Times 3 -ParameterFilter { $Disable.IsPresent }
        Should -Invoke Set-CIPPMailboxRule -Times 0 -ParameterFilter { $RuleName -eq 'Junk E-Mail Rule' }
    }

    It 'restricts itself to the requested rules by identity or name' {
        $Rows = @(Disable-CIPPInboxRules -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -RuleIds @('Forward all'))
        $Rows.Count | Should -Be 1
        $Rows[0].state | Should -Be 'success'
        $Rows[0].resultText | Should -Be 'Disabled 1 inbox rule(s) for victim@contoso.com.'
        Should -Invoke Set-CIPPMailboxRule -Times 1 -ParameterFilter { $RuleId -eq 'victim\2' }
    }

    It 'reports a failing rule as an error row and still disables the rest' {
        Mock Set-CIPPMailboxRule { if ($RuleName -eq 'Hide invoices') { throw 'EXO said no' }; 'ok' }
        $Rows = @(Disable-CIPPInboxRules -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -RuleIds @('Hide invoices', 'Forward all'))
        ($Rows | Where-Object { $_.state -eq 'error' }).resultText | Should -Match "Could not disable rule 'Hide invoices': EXO said no"
        ($Rows | Where-Object { $_.state -eq 'success' }).resultText | Should -Be 'Disabled 1 inbox rule(s) for victim@contoso.com.'
    }
}

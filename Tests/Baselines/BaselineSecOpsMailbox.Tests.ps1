# SecOpsMailbox: the SecOps override policy and its rule (Defender advanced delivery). Tests pin
# the grading decisions that fail silently - a rule bound to the wrong policy, a second rule
# pending deletion, additive-vs-strict mailbox ownership - and the write order that must never
# leave the tenant holding two rules or touch the valid one.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
    function Get-CIPPTable { param($tablename) @{ Name = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Name, $Filter, $Property) }
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Helpers/Test-CIPPBaselineCacheCollected.ps1')
    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineSecOpsMailboxState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineSecOpsMailbox.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
    function New-SecOpsItem {
        param($SentTo = @('report@contoso.com'), $RemoveExtra = $false)
        [PSCustomObject]@{ Variables = [PSCustomObject]@{ SentTo = $SentTo; RemoveExtraMailboxes = $RemoveExtra } }
    }
    function Set-SecOpsCache {
        param($Policies, $Rules)
        $script:CachedPolicies = @($Policies | ConvertTo-Cached)
        $script:CachedRules = @($Rules | ConvertTo-Cached)
        Mock New-CIPPDbRequest {
            switch ($Type) {
                'ExoSecOpsOverridePolicy' { $script:CachedPolicies }
                'ExoSecOpsOverrideRule' { $script:CachedRules }
            }
        }
    }
    $script:Policy = @{ Name = 'SecOpsOverridePolicy'; Identity = 'SecOpsOverridePolicy'; ExternalIdentity = 'ext-policy-1'; Enabled = $true; SentTo = @('report@contoso.com') }
    $script:GoodRule = @{ Name = '_Exe:SecOpsOverrid:1'; Identity = '_Exe:SecOpsOverrid:1'; Policy = 'ext-policy-1'; Mode = 'Enforce'; Disabled = $false }
    Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
}

Describe 'Get-CIPPBaselineSecOpsMailboxState' {
    It 'grades one enabled policy listing the mailbox and one valid bound rule as compliant' {
        Set-SecOpsCache -Policies @($script:Policy) -Rules @($script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'compares addresses case-insensitively' {
        Set-SecOpsCache -Policies @(@{ Name = 'SecOpsOverridePolicy'; ExternalIdentity = 'ext-policy-1'; Enabled = $true; SentTo = @('Report@Contoso.com') }) -Rules @($script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem -SentTo @('REPORT@Contoso.com')) -TenantFilter $script:Tenant
        @($Prepared.Current.missingMailboxes).Count | Should -Be 0
        $Prepared.Current.wantedMailboxes | Should -BeExactly @('report@contoso.com')
    }

    It 'grades a missing mailbox on the policy leg' {
        Set-SecOpsCache -Policies @($script:Policy) -Rules @($script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem -SentTo @('report@contoso.com', 'soc@contoso.com')) -TenantFilter $script:Tenant
        $Prepared.Current.missingMailboxes | Should -Be @('soc@contoso.com')
        $Prepared.Current.validRule | Should -BeTrue
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'grades a disabled policy as drift even when it lists the mailbox' {
        Set-SecOpsCache -Policies @(@{ Name = 'SecOpsOverridePolicy'; ExternalIdentity = 'ext-policy-1'; Enabled = $false; SentTo = @('report@contoso.com') }) -Rules @($script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem) -TenantFilter $script:Tenant
        $Prepared.Current.policyEnabled | Should -BeFalse
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'is additive by default: a hand-added SecOps mailbox is not drift' {
        Set-SecOpsCache -Policies @(@{ Name = 'SecOpsOverridePolicy'; ExternalIdentity = 'ext-policy-1'; Enabled = $true; SentTo = @('report@contoso.com', 'other@contoso.com') }) -Rules @($script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem) -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'extraMailboxes'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'strict mode grades mailboxes outside the list as removals' {
        Set-SecOpsCache -Policies @(@{ Name = 'SecOpsOverridePolicy'; ExternalIdentity = 'ext-policy-1'; Enabled = $true; SentTo = @('report@contoso.com', 'other@contoso.com') }) -Rules @($script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem -RemoveExtra $true) -TenantFilter $script:Tenant
        $Prepared.Current.extraMailboxes | Should -Be @('other@contoso.com')
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'keeps the valid rule and grades a second rule pending deletion as invalid, carrying its identity' {
        $Pending = @{ Name = '_Exe:SecOpsOverrid:2'; Identity = '_Exe:SecOpsOverrid:2'; Policy = 'ext-policy-1'; Mode = 'Enforce'; Disabled = $true }
        Set-SecOpsCache -Policies @($script:Policy) -Rules @($Pending, $script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem) -TenantFilter $script:Tenant
        $Prepared.Current.validRule | Should -BeTrue
        $Prepared.Current.invalidRules | Should -Be @('_Exe:SecOpsOverrid:2')
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'grades a rule in Audit mode or bound to another policy as invalid' {
        $Audit = @{ Name = 'r-audit'; Identity = 'r-audit'; Policy = 'ext-policy-1'; Mode = 'Audit'; Disabled = $false }
        $Orphan = @{ Name = 'r-orphan'; Identity = 'r-orphan'; Policy = 'ext-old-policy'; Mode = 'Enforce'; Disabled = $false }
        Set-SecOpsCache -Policies @($script:Policy) -Rules @($Audit, $Orphan)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem) -TenantFilter $script:Tenant
        $Prepared.Current.validRule | Should -BeFalse
        @($Prepared.Current.invalidRules) | Should -Be @('r-audit', 'r-orphan')
    }

    It 'returns No Data when the cache was never collected, not a compliant empty tenant' {
        Set-SecOpsCache -Policies @() -Rules @()
        Mock Get-CIPPDbItem { }
        Mock Test-CIPPBaselineCacheCollected { $false }
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem) -TenantFilter $script:Tenant
        $Prepared.Current | Should -BeNullOrEmpty
    }

    It 'grades a collected tenant with no policy and no rule as drift on both legs' {
        Set-SecOpsCache -Policies @() -Rules @()
        Mock Test-CIPPBaselineCacheCollected { $true }
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem) -TenantFilter $script:Tenant
        $Prepared.Current.policyExists | Should -BeFalse
        $Prepared.Current.policyEnabled | Should -BeFalse
        $Prepared.Current.validRule | Should -BeFalse
    }

    It 'flags a configuration error when no mailbox is configured' {
        Set-SecOpsCache -Policies @($script:Policy) -Rules @($script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem -SentTo @()) -TenantFilter $script:Tenant
        $Prepared.ConfigError | Should -BeTrue
    }

    It 'names the invalid address as the reason, so the engine never runs the executor' {
        Set-SecOpsCache -Policies @($script:Policy) -Rules @($script:GoodRule)
        $Prepared = Get-CIPPBaselineSecOpsMailboxState -Item (New-SecOpsItem -SentTo @('not-an-address')) -TenantFilter $script:Tenant
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.ConfigError | Should -BeTrue
        $Prepared.NoDataReason | Should -BeLike "*'not-an-address' is not a valid email address"
    }
}

Describe 'Invoke-CIPPBaselineSecOpsMailbox' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        Mock New-ExoRequest { $script:Calls.Add($cmdlet) }
    }

    It 'throws and writes nothing when the prepare hook produced no state' {
        { Invoke-CIPPBaselineSecOpsMailbox -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null } | Should -Throw '*no state to write from*'
        $script:Calls.Count | Should -Be 0
    }

    It 'creates the policy with the configured mailboxes, then the rule, when neither exists' {
        $Current = [PSCustomObject]@{ policyExists = $false; policyEnabled = $false; missingMailboxes = @('report@contoso.com'); validRule = $false; invalidRules = @(); wantedMailboxes = @('report@contoso.com') }
        Invoke-CIPPBaselineSecOpsMailbox -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        $script:Calls | Should -Be @('New-SecOpsOverridePolicy', 'New-ExoSecOpsOverrideRule')
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-SecOpsOverridePolicy' -and @($cmdParams.SentTo) -contains 'report@contoso.com' }
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-ExoSecOpsOverrideRule' -and $cmdParams.Policy -eq 'SecOpsOverridePolicy' }
    }

    It 'uses add/remove DELTAS on an existing policy, never a replacement list' {
        $Current = [PSCustomObject]@{ policyExists = $true; policyEnabled = $true; missingMailboxes = @('soc@contoso.com'); extraMailboxes = @('old@contoso.com'); validRule = $true; invalidRules = @(); wantedMailboxes = @('report@contoso.com', 'soc@contoso.com') }
        Invoke-CIPPBaselineSecOpsMailbox -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-SecOpsOverridePolicy' -and @($cmdParams.AddSentTo) -contains 'soc@contoso.com' -and
            @($cmdParams.RemoveSentTo) -contains 'old@contoso.com' -and -not $cmdParams.ContainsKey('SentTo') -and -not $cmdParams.ContainsKey('Enabled')
        }
    }

    It 're-enables a disabled policy without resending its mailboxes' {
        $Current = [PSCustomObject]@{ policyExists = $true; policyEnabled = $false; missingMailboxes = @(); validRule = $true; invalidRules = @(); wantedMailboxes = @('report@contoso.com') }
        Invoke-CIPPBaselineSecOpsMailbox -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Set-SecOpsOverridePolicy' -and $cmdParams.Enabled -eq $true -and -not $cmdParams.ContainsKey('AddSentTo') }
    }

    It 'removes invalid rules BEFORE creating the missing valid one, so two rules never coexist' {
        $Current = [PSCustomObject]@{ policyExists = $true; policyEnabled = $true; missingMailboxes = @(); validRule = $false; invalidRules = @('r-audit'); wantedMailboxes = @('report@contoso.com') }
        Invoke-CIPPBaselineSecOpsMailbox -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        $script:Calls | Should -Be @('Remove-ExoSecOpsOverrideRule', 'New-ExoSecOpsOverrideRule')
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Remove-ExoSecOpsOverrideRule' -and $cmdParams.Identity -eq 'r-audit' }
    }

    It 'removes only the invalid rule and never recreates when a valid rule remains' {
        $Current = [PSCustomObject]@{ policyExists = $true; policyEnabled = $true; missingMailboxes = @(); validRule = $true; invalidRules = @('_Exe:SecOpsOverrid:2'); wantedMailboxes = @('report@contoso.com') }
        Invoke-CIPPBaselineSecOpsMailbox -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        $script:Calls | Should -Be @('Remove-ExoSecOpsOverrideRule')
    }

    It 'still creates the valid rule when removing a stale invalid rule fails (already deleted since the cache read)' {
        Mock New-ExoRequest { $script:Calls.Add($cmdlet); if ($cmdlet -eq 'Remove-ExoSecOpsOverrideRule') { throw "Couldn't find object $($cmdParams.Identity)" } }
        $Current = [PSCustomObject]@{ policyExists = $true; policyEnabled = $true; missingMailboxes = @(); validRule = $false; invalidRules = @('_Exe:SecOpsOverrid:gone'); wantedMailboxes = @('report@contoso.com') }
        { Invoke-CIPPBaselineSecOpsMailbox -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current } | Should -Not -Throw
        $script:Calls | Should -Be @('Remove-ExoSecOpsOverrideRule', 'New-ExoSecOpsOverrideRule')
    }
}

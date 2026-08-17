# Post-remediation cache verification. A one-off's inline refresh can capture PRE-write
# state on lag-prone Graph surfaces, and a present-but-stale cache never re-collects, so
# the fixed drift re-detects until the next scheduled collection. These tests pin the fix:
# the engine's GradeOnly pass persists NOTHING, and the oneoff branch re-collects exactly
# once when the refreshed cache still grades drifted.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Set-CIPPDBCacheTestCache { param($TenantFilter) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineStandard.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Baselines/Push-CIPPBaselineStandard.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = [PSCustomObject]@{
        name                 = 'TestStd'; label = 'Test Standard'
        requiredCapabilities = @()
        variables            = [PSCustomObject]@{}
        read                 = [PSCustomObject]@{ cacheType = 'TestCache' }
        expected             = [PSCustomObject]@{ enabled = $true }
    }
    $script:EngineItem = @{
        TenantFilter = $script:Tenant; Standard = 'TestStd'; BaseName = 'TestStd'
        Variables = [PSCustomObject]@{}; Tiers = @(); AlertEnabled = $false
    }
}

Describe 'Invoke-CIPPBaselineStandard -GradeOnly' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult { }
        Mock Add-CIPPBaselineHistoryEvent { }
        Mock Send-CIPPBaselineAlert { }
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Write-LogMessage { }
    }

    It 'returns the verdict and persists NOTHING - no history, no alignment, no alerts, no logs' {
        Mock New-CIPPDbRequest { [PSCustomObject]@{ enabled = $true } }
        $Verdict = Invoke-CIPPBaselineStandard -Item $script:EngineItem -Mode 'oneoff' -GradeOnly
        $Verdict.Compliant | Should -BeTrue
        Should -Invoke Set-CIPPBaselineResult -Times 0 -Exactly
        Should -Invoke Add-CIPPBaselineHistoryEvent -Times 0 -Exactly
        Should -Invoke Send-CIPPBaselineAlert -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'grades a still-stale cache non-compliant with the diff, still writing nothing' {
        Mock New-CIPPDbRequest { [PSCustomObject]@{ enabled = $false } }
        $Verdict = Invoke-CIPPBaselineStandard -Item $script:EngineItem -Mode 'oneoff' -GradeOnly
        $Verdict.Compliant | Should -BeFalse
        @($Verdict.Diff).Count | Should -BeGreaterThan 0
        Should -Invoke Set-CIPPBaselineResult -Times 0 -Exactly
    }

    It 'grades an EMPTY cache non-compliant so the caller retries honestly' {
        Mock New-CIPPDbRequest { @() }
        (Invoke-CIPPBaselineStandard -Item $script:EngineItem -Mode 'oneoff' -GradeOnly).Compliant | Should -BeFalse
    }

    It 'a verification that CRASHES returns null without overwriting the optimistic row' {
        Mock New-CIPPDbRequest { throw 'transient table outage' }
        Invoke-CIPPBaselineStandard -Item $script:EngineItem -Mode 'oneoff' -GradeOnly | Should -BeNullOrEmpty
        Should -Invoke Set-CIPPBaselineResult -Times 0 -Exactly
    }

    It 'control: the same fixture WITHOUT GradeOnly persists the result - quietness is the switch, not the harness' {
        Mock New-CIPPDbRequest { [PSCustomObject]@{ enabled = $true } }
        $Result = Invoke-CIPPBaselineStandard -Item $script:EngineItem -Mode 'compare'
        $Result.Compliant | Should -BeTrue
        Should -Invoke Set-CIPPBaselineResult -Times 1 -Exactly
    }
}

Describe 'Invoke-CIPPBaselineStandard render option-unwrap' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult { }
        Mock Add-CIPPBaselineHistoryEvent { }
        Mock Send-CIPPBaselineAlert { }
        Mock Write-LogMessage { }
    }

    It 'unwraps option objects and option arrays before splicing them into the spec' {
        # A declarative standard with picker variables: the saved values are wrappers
        # ({label, value}); the render must splice the VALUES, or the write ships
        # '@{label=...}' strings (single) or raw objects (arrays) to the API.
        Mock Get-CIPPBaselineDefinition { [PSCustomObject]@{
                name = 'RenderStd'; label = 'Render Standard'; requiredCapabilities = @(); variables = [PSCustomObject]@{}
                read = [PSCustomObject]@{ cacheType = 'TestCache' }
                expected = [PSCustomObject]@{ picked = '%MyPick%'; recipients = '%MyList%' }
            } }
        Mock New-CIPPDbRequest { [PSCustomObject]@{ picked = 'one'; recipients = @('a@x.com', 'b@x.com') } }
        $Item = @{
            TenantFilter = $script:Tenant; Standard = 'RenderStd'; BaseName = 'RenderStd'
            Variables = [PSCustomObject]@{
                MyPick = [PSCustomObject]@{ label = 'Option One'; value = 'one' }
                MyList = @([PSCustomObject]@{ label = 'A'; value = 'a@x.com' }, [PSCustomObject]@{ label = 'B'; value = 'b@x.com' })
            }
            Tiers = @(); AlertEnabled = $false
        }
        $Result = Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare'
        $Result.ExpectedValue.picked | Should -Be 'one'
        @($Result.ExpectedValue.recipients) | Should -Be @('a@x.com', 'b@x.com')
        $Result.Compliant | Should -BeTrue
    }

    It 'prepare hooks receive UNWRAPPED variables - direct interpolation gets the value, not the wrapper' {
        # Hooks read $Item.Variables directly (no render pass); a hook interpolating a
        # picker variable raw graded '@{label=...}' against every object and made the
        # whole tenant an offender.
        function Get-CIPPBaselineHookProbeState { param($Item, $TenantFilter)
            $script:HookSawVariable = $Item.Variables.MyPick
            @{ Expected = [PSCustomObject]@{ ok = $true }; Current = [PSCustomObject]@{ ok = $true } }
        }
        Mock Get-CIPPBaselineDefinition { [PSCustomObject]@{
                name = 'HookProbe'; label = 'Hook Probe'; requiredCapabilities = @(); variables = [PSCustomObject]@{}
                read = [PSCustomObject]@{ cacheType = 'TestCache' }
                prepare = 'Get-CIPPBaselineHookProbeState'
            } }
        $script:HookSawVariable = $null
        $Item = @{
            TenantFilter = $script:Tenant; Standard = 'HookProbe'; BaseName = 'HookProbe'
            Variables = @{ MyPick = [ordered]@{ label = 'Option One'; value = 'one' } }   # hashtable-shaped, as the durable pipeline delivers
            Tiers = @(); AlertEnabled = $false
        }
        $null = Invoke-CIPPBaselineStandard -Item $Item -Mode 'compare'
        $script:HookSawVariable | Should -Be 'one'
    }
}

Describe 'Invoke-CIPPBaselineGraphBulkSweep batch ids' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineGraphBulkSweep.ps1')
        function New-GraphBulkRequest { param($tenantid, $Requests, $scope, $asapp, $Version) }
    }

    It 'every batch request carries a non-empty sequential id - Graph rejects empty ids outright' {
        # "$($Index++)" emits NOTHING in PowerShell, which shipped every request with an
        # empty id and failed every sweep with 'Id property cannot be empty'.
        $script:CapturedRequests = $null
        Mock New-GraphBulkRequest {
            $script:CapturedRequests = @($Requests)
            @($Requests | ForEach-Object { [PSCustomObject]@{ id = $_.id; status = 204 } })
        }
        $Remediate = [PSCustomObject]@{ writes = @([PSCustomObject]@{ method = 'PATCH'; uri = 'users/%id%'; body = [PSCustomObject]@{ accountEnabled = $false } }) }
        $Current = [PSCustomObject]@{ targets = @([PSCustomObject]@{ id = 'user-1' }, [PSCustomObject]@{ id = 'user-2' }) }
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $Remediate -TenantFilter $script:Tenant -Current $Current
        @($script:CapturedRequests | ForEach-Object { "$($_.id)" }) | Should -Be @('0', '1')
        @($script:CapturedRequests)[1].url | Should -Be '/users/user-2'
    }
}

Describe 'Convert-CIPPBaselineResolvedEntity identity labels' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Convert-CIPPBaselineResolvedEntity.ps1')
        $script:InstanceDefs = @([PSCustomObject]@{ name = 'CATemplate'; label = 'Conditional Access Template'; instanceIdentity = 'caTemplate'; remediate = [PSCustomObject]@{ executor = 'CATemplate' } })
    }

    It 'unwraps an option-object identity from the inheritance instead of stringifying it' {
        # The stored inheritance carries the picker's {label, value} object; the label
        # suffix must be the value, never '@{label=...; value=...}'.
        $Entity = [PSCustomObject]@{
            PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'CATemplate~abc'; StandardName = 'CATemplate#abc'
            ExpectedValue = $null; Inheritance = (@(@{ effective = $true; value = @{ caTemplate = @{ label = 'CA003-Policy'; value = 'guid-1' } } }) | ConvertTo-Json -Depth 10)
            Status = 'Drift'
        }
        $Row = Convert-CIPPBaselineResolvedEntity -Entity $Entity -Definitions $script:InstanceDefs
        $Row.standardLabel | Should -Be 'Conditional Access Template - guid-1'
        $Row.standardLabel | Should -Not -Match '@\{'
    }
}

Describe 'Get-CIPPBaselineDisableInactiveUsersState exclusions' {
    BeforeAll {
        function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType, $CollectorArgs) }
        function Test-CIPPBaselineCacheCollected { param($TenantFilter, $Type) $true }
        function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $scope) }
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineDisableInactiveUsersState.ps1')
    }

    It 'excluded accounts are never offenders - a breakglass account must not be sweep-disabled' {
        $Old = (Get-Date).AddDays(-400).ToUniversalTime().ToString('o')
        Mock New-CIPPDbRequest { @(
                [PSCustomObject]@{ id = 'u1'; userPrincipalName = 'breakglass@contoso.com'; userType = 'Member'; accountEnabled = $true; onPremisesSyncEnabled = $false; createdDateTime = $Old; signInActivity = [PSCustomObject]@{ lastSuccessfulSignInDateTime = $Old } }
                [PSCustomObject]@{ id = 'u2'; userPrincipalName = 'stale@contoso.com'; userType = 'Member'; accountEnabled = $true; onPremisesSyncEnabled = $false; createdDateTime = $Old; signInActivity = [PSCustomObject]@{ lastSuccessfulSignInDateTime = $Old } }
            ) }
        Mock New-GraphGetRequest { @() }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ days = 180; excludedUsers = @([PSCustomObject]@{ value = 'breakglass@contoso.com' }) } }
        $Prepared = Get-CIPPBaselineDisableInactiveUsersState -Item $Item -TenantFilter 'contoso.onmicrosoft.com'
        @($Prepared.Current.offenders) | Should -Be @('stale@contoso.com')
        @($Prepared.Current.targets | ForEach-Object { $_.id }) | Should -Be @('u2')
    }
}

Describe 'Invoke-CIPPBaselineExoPolicyRule extraPolicyParams' {
    BeforeAll {
        function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineExoPolicyRule.ps1')
    }

    It 'merges hook-derived policy params over the rendered spec - grade and write share one derivation' {
        Mock New-ExoRequest { }
        $Remediate = [PSCustomObject]@{
            policyCmdlet = 'HostedContentFilterPolicy'; ruleCmdlet = 'HostedContentFilterRule'
            policyParams = [PSCustomObject]@{ SpamAction = 'Quarantine'; BulkThreshold = 7 }
            ruleParams   = [PSCustomObject]@{ Priority = 0 }
        }
        $Current = [PSCustomObject]@{
            policyName = 'CIPP Spam Policy'; policyExists = $true; ruleName = 'CIPP Spam Policy'; ruleExists = $true
            ruleLinkedPolicy = 'CIPP Spam Policy'; acceptedDomains = @('contoso.com'); skipRule = $false
            extraPolicyParams = [PSCustomObject]@{ MarkAsSpamFramesInHtml = 'On'; BulkThreshold = 9 }
        }
        Invoke-CIPPBaselineExoPolicyRule -Remediate $Remediate -TenantFilter 'contoso.onmicrosoft.com' -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-HostedContentFilterPolicy' -and
            $cmdParams.MarkAsSpamFramesInHtml -eq 'On' -and
            $cmdParams.BulkThreshold -eq 9 -and
            $cmdParams.SpamAction -eq 'Quarantine'
        }
    }
}

Describe 'Invoke-CIPPBaselineEnableFIDO2 passkey profile normalization' {
    BeforeAll {
        function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
        function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp, $ContentType) }
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineEnableFIDO2.ps1')
    }

    It 'gives profiles missing keyRestrictions the neutral shape before the PATCH - Graph validates the whole config' {
        Mock New-GraphGetRequest { [PSCustomObject]@{
                state = 'disabled'; isAttestationEnforced = $false; isSelfServiceRegistrationAllowed = $false
                passkeyProfiles = @(
                    [PSCustomObject]@{ displayName = 'Legacy'; },
                    [PSCustomObject]@{ displayName = 'Modern'; keyRestrictions = [PSCustomObject]@{ isEnforced = $true; enforcementType = 'allow'; aaGuids = @('g1') } }
                )
            } }
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineEnableFIDO2 -Remediate ([PSCustomObject]@{}) -TenantFilter 'contoso.onmicrosoft.com' -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $AsApp -eq $true -and
            ($body | ConvertFrom-Json).state -eq 'enabled' -and
            @(($body | ConvertFrom-Json).passkeyProfiles)[0].keyRestrictions.isEnforced -eq $false -and
            @(($body | ConvertFrom-Json).passkeyProfiles)[1].keyRestrictions.enforcementType -eq 'allow'
        }
    }
}

Describe 'Get-CIPPBaselineDetectCADriftState SharePoint side-effect policies' {
    BeforeAll {
        function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
        function Get-CIPPBaselineWorkItems { param($TenantFilter) }
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineDetectCADriftState.ps1')
    }
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 2 } }
        Mock New-CIPPDbRequest { @(
                [PSCustomObject]@{ displayName = '[SharePoint admin center]Use app-enforced Restrictions for browser access - 2026/08/17'; state = 'enabled'; id = 'sp-1' }
                [PSCustomObject]@{ displayName = 'Rogue Admin Policy'; state = 'enabled'; id = 'rogue-1' }
            ) }
    }

    It 'does not flag [SharePoint admin center] policies when an unmanaged-device access standard applies' {
        # unmanagedSync/OWAAttachmentRestrictions turn on app-enforced restrictions, and
        # SharePoint auto-creates these CA policies - a managed side-effect, not drift.
        Mock Get-CIPPBaselineWorkItems { @([PSCustomObject]@{ BaseName = 'unmanagedSync'; Variables = [PSCustomObject]@{} }) }
        $Prepared = Get-CIPPBaselineDetectCADriftState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter 'contoso.onmicrosoft.com'
        @($Prepared.Current.PSObject.Properties.Name) | Should -Not -Contain '[SharePoint admin center]Use app-enforced Restrictions for browser access - 2026/08/17'
        @($Prepared.Current.PSObject.Properties.Name) | Should -Contain 'Rogue Admin Policy'
    }

    It 'still flags [SharePoint admin center] policies when NO access standard applies - then somebody clicked the portal' {
        Mock Get-CIPPBaselineWorkItems { @() }
        $Prepared = Get-CIPPBaselineDetectCADriftState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter 'contoso.onmicrosoft.com'
        @($Prepared.Current.PSObject.Properties.Name) | Should -Contain '[SharePoint admin center]Use app-enforced Restrictions for browser access - 2026/08/17'
    }
}

Describe 'Push-CIPPBaselineStandard oneoff verification' {
    BeforeEach {
        $script:GradeCalls = 0
        Mock Set-CippBaselineRunContext { }
        Mock Set-CIPPDBCacheTestCache { }
        Mock Start-Sleep { }
        Mock Write-LogMessage { }
        $script:PushItem = @{
            RunId = 'run-1'; Mode = 'oneoff'; TriggeredBy = 'operator@contoso.com'
            Item  = @{ TenantFilter = $script:Tenant; Standard = 'TestStd'; BaseName = 'TestStd' }
        }
    }

    It 'fresh on the first grade: one refresh, one grade, no sleep, no warning' {
        Mock Invoke-CIPPBaselineStandard {
            if ($GradeOnly) { $script:GradeCalls++; return [PSCustomObject]@{ Compliant = $true } }
            [PSCustomObject]@{ Remediated = $true; CacheType = @('TestCache') }
        }
        Push-CIPPBaselineStandard -Item $script:PushItem
        Should -Invoke Set-CIPPDBCacheTestCache -Times 1 -Exactly
        $script:GradeCalls | Should -Be 1
        Should -Invoke Start-Sleep -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $Sev -eq 'Warning' }
    }

    It 'stale then fresh: waits for propagation, collects a SECOND time, ends quiet' {
        # The whole point of the fix - the first refresh captured pre-write state, the
        # retry after the backoff captures the real one.
        Mock Invoke-CIPPBaselineStandard {
            if ($GradeOnly) { $script:GradeCalls++; return [PSCustomObject]@{ Compliant = ($script:GradeCalls -ge 2) } }
            [PSCustomObject]@{ Remediated = $true; CacheType = @('TestCache') }
        }
        Push-CIPPBaselineStandard -Item $script:PushItem
        Should -Invoke Set-CIPPDBCacheTestCache -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly
        $script:GradeCalls | Should -Be 2
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $Sev -eq 'Warning' }
    }

    It 'still stale after BOTH retries: warns and STOPS - two growing backoffs, never a loop' {
        Mock Invoke-CIPPBaselineStandard {
            if ($GradeOnly) { $script:GradeCalls++; return [PSCustomObject]@{ Compliant = $false } }
            [PSCustomObject]@{ Remediated = $true; CacheType = @('TestCache') }
        }
        Push-CIPPBaselineStandard -Item $script:PushItem
        Should -Invoke Set-CIPPDBCacheTestCache -Times 3 -Exactly
        $script:GradeCalls | Should -Be 3
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 30 }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*still grades*' }
    }

    It 'scheduled runs are untouched: impact records out, no inline refresh, no verification' {
        Mock Invoke-CIPPBaselineStandard {
            if ($GradeOnly) { $script:GradeCalls++; return [PSCustomObject]@{ Compliant = $true } }
            [PSCustomObject]@{ Remediated = $true; CacheType = @('TestCache') }
        }
        $script:PushItem.Mode = 'run'
        $Records = @(Push-CIPPBaselineStandard -Item $script:PushItem)
        $Records.Count | Should -Be 1
        $Records[0].CacheType | Should -Be 'TestCache'
        Should -Invoke Set-CIPPDBCacheTestCache -Times 0 -Exactly
        $script:GradeCalls | Should -Be 0
    }
}

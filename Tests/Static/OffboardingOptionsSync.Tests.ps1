# Every offboarding option is wired by hand into the validator, the job, the wizard and four defaults
# editors. Test-CIPPOffboardingRequest's action lists are the source of truth; a new option that misses
# one of the other places fails here instead of silently never running or never saving as a default.

BeforeDiscovery {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
    $script:HasFrontend = Test-Path (Join-Path $script:RepoRoot 'frontend/src')
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
    $Read = { param($Path) [System.IO.File]::ReadAllText((Join-Path $RepoRoot $Path)) }

    $ValidatorPath = Join-Path $RepoRoot 'backend/Modules/CIPPCore/Public/Test-CIPPOffboardingRequest.ps1'
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($ValidatorPath, [ref]$null, [ref]$null)
    $GetList = {
        param($Name)
        $Assignment = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq "`$$Name" }, $true)
        @($Assignment.Right.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value)
    }
    $script:BooleanActions = & $GetList 'BooleanActions'
    $script:CollectionActions = & $GetList 'CollectionActions'
    if ($script:BooleanActions.Count -lt 15 -or $script:CollectionActions.Count -lt 3) { throw 'Could not read the action lists from Test-CIPPOffboardingRequest' }

    # Per-run choices that are not saved as defaults.
    $script:DefaultKeys = @($script:BooleanActions | Where-Object { $_ -notin @('disableForwarding') })
    # Non-action inputs the job and the defaults also carry.
    $script:Companions = @('KeepCopy', 'NewGroupOwner', 'OOO', 'forward')

    $script:Job = & $Read 'backend/Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1'
    if (Test-Path (Join-Path $RepoRoot 'frontend/src')) {
        $script:Wizard = & $Read 'frontend/src/components/CippWizard/CippWizardOffboarding.jsx'
        $script:DefaultPanel = & $Read 'frontend/src/components/CippComponents/CippOffboardingDefaultSettings.jsx'
        $script:SideBar = & $Read 'frontend/src/components/CippComponents/CippSettingsSideBar.jsx'
        $script:TenantEditors = @{
            'tenant/administration/tenants/edit.jsx' = & $Read 'frontend/src/pages/tenant/administration/tenants/edit.jsx'
            'tenant/manage/edit.jsx'                 = & $Read 'frontend/src/pages/tenant/manage/edit.jsx'
        }
    }

    $Missing = { param($Keys, $Text, $Pattern) @($Keys | Where-Object { $Text -notmatch ($Pattern -f [regex]::Escape($_)) }) }
}

Describe 'Offboarding options stay in sync' {
    It 'every validator action is handled by Invoke-CIPPOffboardingJob' {
        & $Missing ($BooleanActions + $CollectionActions) $Job '\$Options\.{0}\b' | Should -BeNullOrEmpty
    }

    It 'every option the job reads is in the validator lists' {
        $Known = $BooleanActions + $CollectionActions + $Companions
        @([regex]::Matches($Job, '\$Options\.(\w+)').ForEach({ $_.Groups[1].Value }) | Sort-Object -Unique | Where-Object { $_ -notin $Known }) |
            Should -BeNullOrEmpty -Because 'an action missing from Test-CIPPOffboardingRequest does not count as a selected action'
    }

    It 'every action has a wizard field' -Skip:(-not $HasFrontend) {
        & $Missing ($BooleanActions + $CollectionActions) $Wizard 'name="{0}"' | Should -BeNullOrEmpty
    }

    It 'every action is cleared by the wizard when Delete User is selected' -Skip:(-not $HasFrontend) {
        & $Missing @($BooleanActions | Where-Object { $_ -ne 'DeleteUser' }) $Wizard "setValue\('{0}', false\)" | Should -BeNullOrEmpty
    }

    It 'every default has a switch in the user defaults panel' -Skip:(-not $HasFrontend) {
        & $Missing $DefaultKeys $DefaultPanel 'name="offboardingDefaults\.{0}"' | Should -BeNullOrEmpty
    }

    It 'every default is saved from the preferences sidebar' -Skip:(-not $HasFrontend) {
        & $Missing $DefaultKeys $SideBar '\b{0}: formValues\.offboardingDefaults\?\.{0}\b' | Should -BeNullOrEmpty
    }

    It 'the defaults editors hold no option the validator does not know' -Skip:(-not $HasFrontend) {
        $Known = $DefaultKeys + $Companions
        @([regex]::Matches($DefaultPanel + $SideBar, 'offboardingDefaults\??\.(\w+)').ForEach({ $_.Groups[1].Value }) |
            Sort-Object -Unique | Where-Object { $_ -notin $Known -and $_ -ne 'postExecution' }) | Should -BeNullOrEmpty
    }

    It 'every default is in both blocks of <_>' -Skip:(-not $HasFrontend) -ForEach @('tenant/administration/tenants/edit.jsx', 'tenant/manage/edit.jsx') {
        $Text = $TenantEditors[$_]
        @($DefaultKeys | Where-Object { [regex]::Matches($Text, ('\b{0}: false' -f [regex]::Escape($_))).Count -lt 2 }) |
            Should -BeNullOrEmpty -Because 'the initial values and the reset values both list every default'
    }
}

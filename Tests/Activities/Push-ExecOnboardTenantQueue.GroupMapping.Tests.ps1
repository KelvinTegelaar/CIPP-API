# Onboarding step 3 must finish a pending invite's group mapping even when the relationship already has
# some access assignments, or a group that failed (or was never mapped) is reported as done. The step is
# run on its own, lifted from the activity up to the mapping decision, because later steps poll Graph.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Path = Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-ExecOnboardTenantQueue.ps1'
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $Step3 = $Ast.Find({ param($Node)
            $Node -is [System.Management.Automation.Language.IfStatementAst] -and
            $Node.Clauses[0].Item1.Extent.Text -eq "`$OnboardingSteps.Step2.Status -eq 'succeeded'"
        }, $true)
    $Statements = @($Step3.Clauses[0].Item2.Statements)
    $Last = 0
    while (-not ($Statements[$Last] -is [System.Management.Automation.Language.IfStatementAst] -and $Statements[$Last].Clauses[0].Item1.Extent.Text -match 'AutoMapRoles -ne \$true')) { $Last++ }
    $script:Step3Block = [ScriptBlock]::Create(($Statements[0..$Last] | ForEach-Object { $_.Extent.Text }) -join "`n")

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) if ($TableName -eq 'GDAPInvites') { $script:InviteRow } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($Uri) $script:Assignments }
    function Set-CIPPGDAPInviteGroups { param($Relationship) $script:MapCalls++; $script:MapResult }

    function Invoke-Step3 {
        $Id = 'rel-1'
        $Item = [pscustomobject]@{ AutoMapRoles = $null; Roles = $null }
        $Relationship = [pscustomobject]@{ id = $Id; customer = @{ displayName = 'Contoso' } }
        $OnboardingSteps = [pscustomobject]@{ Step3 = [pscustomobject]@{ Status = 'pending'; Message = '' } }
        $TenantOnboarding = [pscustomobject]@{ Status = 'running'; OnboardingSteps = ''; Logs = '' }
        $OnboardTable = @{ TableName = 'TenantOnboarding' }
        $Logs = [System.Collections.Generic.List[object]]::new()
        . $script:Step3Block
        $OnboardingSteps.Step3
    }
}

Describe 'onboarding step 3 group mapping' {
    BeforeEach {
        $script:MapCalls = 0
        $script:MapResult = $true
        $script:Assignments = @([pscustomobject]@{ id = 'a1'; status = 'active'; accessContainer = @{ accessContainerId = 'g-reader' } })
        $script:InviteRow = [pscustomobject]@{ RowKey = 'rel-1'; RoleMappings = '[]' }
    }

    It 'maps the rest of a pending invite when some groups are already mapped' {
        Invoke-Step3 | Out-Null
        $script:MapCalls | Should -Be 1
    }

    It 'fails the step when the remaining groups cannot be mapped' {
        $script:MapResult = $false
        (Invoke-Step3).Status | Should -Be 'failed'
    }

    It 'keeps the already-mapped shortcut when no invite is pending' {
        $script:InviteRow = $null
        $Step = Invoke-Step3
        $script:MapCalls | Should -Be 0
        $Step.Status | Should -Be 'succeeded'
    }
}

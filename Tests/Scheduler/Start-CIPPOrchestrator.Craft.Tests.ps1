BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Start-CIPPOrchestrator.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Resolve-CIPPOrchestratorPriority.ps1')
    function Write-LogMessage { param($message, $tenant, $API, $sev) }

    # Stands in for Craft's bridge with its current signatures: records each queued run, and reports the
    # names in ActiveNames as still running.
    if (-not ('Craft.Services.OrchestratorBridge' -as [type])) {
        Add-Type -TypeDefinition @'
namespace Craft.Services {
    public static class OrchestratorBridge {
        public static System.Collections.Generic.List<object[]> Calls = new System.Collections.Generic.List<object[]>();
        public static System.Collections.Generic.HashSet<string> ActiveNames = new System.Collections.Generic.HashSet<string>();
        public static bool IsRunActive(string name) { return ActiveNames.Contains(name); }
        public static void QueueOrchestrationFromFile(string name, string batchFilePath, int priority,
            string postExecFunctionName, string postExecParametersJson, string reference, string parentRunName,
            bool sequential, bool allowCollision, int maxConcurrency, bool stopOnFailure) {
            Calls.Add(new object[] { name, parentRunName, allowCollision, priority, sequential, maxConcurrency, stopOnFailure });
            System.IO.File.Delete(batchFilePath);
        }
    }
}
'@
    }

    function Invoke-Start ($InputObject) {
        [Craft.Services.OrchestratorBridge]::Calls.Clear()
        $Result = Start-CIPPOrchestrator -InputObject $InputObject
        $Call = @([Craft.Services.OrchestratorBridge]::Calls)[0]
        if ($null -eq $Call) { return [pscustomobject]@{ Result = $Result; Queued = $false } }
        [pscustomobject]@{
            Result = $Result; Queued = $true; Name = $Call[0]; Parent = $Call[1]; AllowCollision = $Call[2]
            Priority = $Call[3]; Sequential = $Call[4]; MaxConcurrency = $Call[5]; StopOnFailure = $Call[6]
        }
    }
}

Describe 'Start-CIPPOrchestrator on Craft' {
    BeforeEach {
        $script:PreviousCippNg = $env:CIPPNG
        $env:CIPPNG = 'true'
        [Craft.Services.OrchestratorBridge]::ActiveNames.Clear()
        Mock Write-LogMessage {}
    }
    AfterEach {
        $env:CIPPNG = $script:PreviousCippNg
        Remove-Variable -Name CraftOperationContext -Scope Global -ErrorAction SilentlyContinue
    }

    It 'lets runs of one name stack up unless told otherwise' {
        [void][Craft.Services.OrchestratorBridge]::ActiveNames.Add('Stacks')
        $Run = Invoke-Start ([pscustomobject]@{ OrchestratorName = 'Stacks'; Batch = @(@{ TenantFilter = 'a.com' }) })
        $Run.Queued | Should -BeTrue
        $Run.AllowCollision | Should -BeTrue
        Should -Invoke Write-LogMessage -Times 0
    }

    It 'passes AllowCollision = $false through to Craft when no run of that name is active' {
        (Invoke-Start ([pscustomobject]@{ OrchestratorName = 'Single'; AllowCollision = $false; Batch = @(@{ TenantFilter = 'a.com' }) })).AllowCollision |
            Should -BeFalse
    }

    It 'skips without collisions while a run of that name is active, and logs it against the tenant' {
        [void][Craft.Services.OrchestratorBridge]::ActiveNames.Add('MailboxRules_a.com')
        $Run = Invoke-Start ([pscustomobject]@{
                OrchestratorName = 'MailboxRules_a.com'; AllowCollision = $false
                Batch            = @(@{ TenantFilter = 'a.com' }, @{ TenantFilter = 'a.com' })
            })
        $Run.Queued | Should -BeFalse
        $Run.Result | Should -Be 'Craft-MailboxRules_a.com-Skipped'
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
            $tenant -eq 'a.com' -and $sev -eq 'Warning' -and $message -like 'Skipped MailboxRules_a.com (2 tasks)*'
        }
    }

    It 'names the parent by its exact run key when Craft stamps one' {
        $global:CraftOperationContext = [pscustomobject]@{ RunName = 'Parent'; RunKey = 'Parent~8de0a1b2c3d4e5f'; Priority = 4 }
        (Invoke-Start ([pscustomobject]@{ OrchestratorName = 'Child'; Batch = @(@{ TenantFilter = 'a.com' }) })).Parent |
            Should -Be 'Parent~8de0a1b2c3d4e5f'
    }

    It 'passes MaxConcurrency and StopOnFailure through, defaulting to no limit and carry on' {
        $Default = Invoke-Start ([pscustomobject]@{ OrchestratorName = 'Plain'; Batch = @(@{ TenantFilter = 'a.com' }) })
        $Default.MaxConcurrency | Should -Be 0
        $Default.StopOnFailure | Should -BeFalse

        $Set = Invoke-Start ([pscustomobject]@{ OrchestratorName = 'Tuned'; MaxConcurrency = 4; Batch = @(@{ TenantFilter = 'a.com' }) })
        $Set.MaxConcurrency | Should -Be 4
        $Seq = Invoke-Start ([pscustomobject]@{ OrchestratorName = 'Steps'; Sequential = $true; StopOnFailure = $true; Batch = @(@{ TenantFilter = 'a.com' }) })
        $Seq.Sequential | Should -BeTrue
        $Seq.StopOnFailure | Should -BeTrue
    }

    It 'gives a child its parent priority and nothing else' {
        $global:CraftOperationContext = [pscustomobject]@{ RunName = 'Parent'; RunKey = 'Parent~8de0a1b2c3d4e5f'; Priority = 7; Category = 'Job' }
        $Child = Invoke-Start ([pscustomobject]@{ OrchestratorName = 'Child'; Batch = @(@{ TenantFilter = 'a.com' }) })
        $Child.Priority | Should -Be 7
        $Child.Sequential | Should -BeFalse
        $Child.MaxConcurrency | Should -Be 0
        $Child.StopOnFailure | Should -BeFalse
        $Child.AllowCollision | Should -BeTrue
    }

    It 'lets a child set its own priority and mode over its parent' {
        $global:CraftOperationContext = [pscustomobject]@{ RunName = 'Parent'; Priority = 7; Category = 'Job' }
        $Child = Invoke-Start ([pscustomobject]@{
                OrchestratorName = 'OwnChild'; Priority = 2; Sequential = $true; StopOnFailure = $true
                Batch            = @(@{ TenantFilter = 'a.com' })
            })
        $Child.Priority | Should -Be 2
        $Child.Sequential | Should -BeTrue
        $Child.StopOnFailure | Should -BeTrue
    }

    It 'warns when it is given an option that does not apply to the run' {
        $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                OrchestratorName = 'SeqCapped'; Sequential = $true; MaxConcurrency = 3; Batch = @(@{ TenantFilter = 'a.com' })
            }) -WarningVariable SeqWarn -WarningAction SilentlyContinue
        "$SeqWarn" | Should -Match 'MaxConcurrency is ignored'

        $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                OrchestratorName = 'FanStop'; StopOnFailure = $true; Batch = @(@{ TenantFilter = 'a.com' })
            }) -WarningVariable FanWarn -WarningAction SilentlyContinue
        "$FanWarn" | Should -Match 'StopOnFailure is ignored'
    }

    It 'falls back to the parent run name on an older Craft that stamps no run key' {
        $global:CraftOperationContext = [pscustomobject]@{ RunName = 'Parent'; Priority = 4 }
        (Invoke-Start ([pscustomobject]@{ OrchestratorName = 'Child'; Batch = @(@{ TenantFilter = 'a.com' }) })).Parent |
            Should -Be 'Parent'
    }
}

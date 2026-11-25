# One activity per standard builds the snapshot a custom managed baseline request sends. It grades
# the standard against CIPP's own defaults in compare-only mode, stores the redacted result, and
# never reads the tenant for a standard that needs a choice only a person can make.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Invoke-CIPPBaselineStandard { param($Item, $Mode, [switch]$GradeOnly) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Test-CIPPManagedBaselineIdentifier.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Protect-CIPPManagedBaselineSnapshot.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineStandardGrade.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Baselines/Push-CIPPManagedBaselineCollect.ps1')

    $script:Item = @{
        RequestId         = 'request-9'
        TenantFilter      = 'contoso.com'
        Standard          = 'SmartLockout'
        InBaseline        = $true
        TenantIdentifiers = @('Contoso Ltd', 'contoso.com')
        QueueId           = 'queue-1'
        QueueName         = 'SmartLockout - contoso.com'
    }
    $script:Defaulted = [pscustomobject]@{
        name      = 'SmartLockout'
        variables = [pscustomobject]@{ LockoutThreshold = [pscustomobject]@{ type = 'number'; default = 10 } }
        expected  = [pscustomobject]@{ lockoutThreshold = '%LockoutThreshold%' }
    }
    $script:Graded = {
        param([bool]$Compliant, $Current, $Diff = @())
        [pscustomobject]@{ Compliant = $Compliant; CurrentValue = $Current; Diff = $Diff }
    }
}

Describe 'Push-CIPPManagedBaselineCollect' {
    BeforeEach {
        $script:Written = $null
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
        Mock Update-CippQueueEntry {}
        Mock Get-CIPPBaselineDefinition { $script:Defaulted }
        Mock Invoke-CIPPBaselineStandard { & $script:Graded $true ([pscustomobject]@{ lockoutThreshold = 10 }) }
    }

    It 'grades against CIPP''s own defaults in compare-only mode' {
        Push-CIPPManagedBaselineCollect -Item $script:Item

        Should -Invoke Invoke-CIPPBaselineStandard -Times 1 -Exactly -ParameterFilter {
            $GradeOnly -and $Mode -eq 'compare' -and $null -eq $Item.Variables -and
            $Item.TenantFilter -eq 'contoso.com' -and $Item.BaseName -eq 'SmartLockout' -and $Item.RemediateEnabled -eq $false
        }
    }

    It 'stores the result redacted, under the request, with the settings that differ' {
        Mock Invoke-CIPPBaselineStandard {
            & $script:Graded $false ([pscustomobject]@{ lockoutThreshold = 5; notify = 'soc@contoso.com' }) @([pscustomobject]@{ Property = 'lockoutThreshold'; ExpectedValue = 10; ReceivedValue = 5 })
        }

        Push-CIPPManagedBaselineCollect -Item $script:Item

        $script:Written.PartitionKey | Should -Be 'request-9'
        $script:Written.RowKey | Should -Be 'SmartLockout'
        $script:Written.Status | Should -Be 'Drift'
        $script:Written.InBaseline | Should -BeTrue
        $script:Written.DiffersOn | Should -Be '["lockoutThreshold"]'
        $Current = $script:Written.Current | ConvertFrom-Json
        $Current.lockoutThreshold | Should -Be 5
        $Current.notify | Should -Be '<redacted>'
        $script:Written.Current | Should -Not -Match 'contoso'
    }

    It 'records <Status> when the engine answers with <Case>' -ForEach @(
        @{ Case = 'a compliant grade'; Status = 'Compliant'; Answer = { & $script:Graded $true ([pscustomobject]@{ lockoutThreshold = 10 }) } }
        @{ Case = 'a grade without a current value'; Status = 'No Data'; Answer = { & $script:Graded $false $null } }
        @{ Case = 'nothing'; Status = 'No Data'; Answer = { $null } }
        @{ Case = 'a licence skip'; Status = 'No licence'; Answer = { [pscustomobject]@{ Outcome = 'Skipped-License'; Status = 'Skipped - No License'; CurrentValue = $null } } }
        @{ Case = 'an error it explains'; Status = 'No Data'; Answer = { [pscustomobject]@{ Outcome = 'Error'; Status = 'Error'; CurrentValue = $null } } }
    ) {
        Mock Invoke-CIPPBaselineStandard $Answer

        Push-CIPPManagedBaselineCollect -Item $script:Item

        $script:Written.Status | Should -Be $Status
        $script:Written.DiffersOn | Should -Be '[]'
    }

    It 'records <Case> as needing a choice without reading the tenant' -ForEach @(
        @{ Case = 'a standard that deploys a chosen template'; Definition = [pscustomobject]@{ name = 'ConditionalAccessTemplate'; instanceIdentity = 'caTemplate'; variables = [pscustomobject]@{ caTemplate = [pscustomobject]@{ type = 'autoComplete'; required = $true } } } }
        @{ Case = 'a required setting without a default'; Definition = [pscustomobject]@{ name = 'NudgeMFA'; variables = [pscustomobject]@{ state = [pscustomobject]@{ type = 'autoComplete'; required = $true } } } }
        @{ Case = 'a setting without a default that the expected value needs'; Definition = [pscustomobject]@{ name = 'Sample'; variables = [pscustomobject]@{ limit = [pscustomobject]@{ type = 'number' } }; expected = [pscustomobject]@{ limit = '%limit%' } } }
    ) {
        Mock Get-CIPPBaselineDefinition { $Definition }

        Push-CIPPManagedBaselineCollect -Item $script:Item

        $script:Written.Status | Should -Be 'Needs a choice'
        $script:Written.Current | Should -Be ''
        Should -Invoke Invoke-CIPPBaselineStandard -Times 0 -Exactly
    }

    It 'still grades a standard whose only blank setting is one that is left out when blank' {
        Mock Get-CIPPBaselineDefinition {
            [pscustomobject]@{ name = 'Sample'; variables = [pscustomobject]@{ note = [pscustomobject]@{ type = 'textField'; omitWhenBlank = $true } }; expected = [pscustomobject]@{ note = '%note%'; enabled = $true } }
        }

        Push-CIPPManagedBaselineCollect -Item $script:Item

        Should -Invoke Invoke-CIPPBaselineStandard -Times 1 -Exactly
        $script:Written.Status | Should -Be 'Compliant'
    }

    It 'still writes a row when the compare throws, so the snapshot is never short a standard' {
        Mock Invoke-CIPPBaselineStandard { throw 'cache exploded' }

        Push-CIPPManagedBaselineCollect -Item $script:Item

        $script:Written.Status | Should -Be 'No Data'
        Should -Invoke Update-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $RowKey -eq 'queue-1' }
    }
}

# The recommendations scan: every recommendation comes from CyberDrain's list, the compare runs
# in CIPP, and a finding keeps the date it was first seen until it is resolved.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, [string]$OperationType) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function New-CippQueueEntry { param($Name, $Reference, $TotalTasks) @{ RowKey = 'queue-1' } }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CIPPBaselineWorkItems { param($TenantFilter) }
    function Invoke-CIPPBaselineStandard { param($Item, $Mode, [switch]$GradeOnly) }
    function Invoke-ManagedBaselinesRequest { param($Path, $Method, $Body) }
    . (Join-Path $BackendRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineStandardGrade.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Baselines/Push-CIPPManagedBaselineRecommendationCollect.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Complete-CIPPManagedBaselineRecommendationScan.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Start-CIPPManagedBaselineRecommendationScan.ps1')

    $script:Tenant = [pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = 'tenant-1'; displayName = 'Contoso Ltd' }
    $script:Definition = [pscustomobject]@{
        name      = 'SmartLockout'
        variables = [pscustomobject]@{ LockoutThreshold = [pscustomobject]@{ type = 'number'; default = 10 } }
        expected  = [pscustomobject]@{ lockoutThreshold = '%LockoutThreshold%' }
    }
    $script:Family = [pscustomobject]@{
        name             = 'ConditionalAccessTemplate'
        instanceIdentity = 'caTemplate'
        variables        = [pscustomobject]@{ caTemplate = [pscustomobject]@{ type = 'autoComplete'; required = $true } }
    }
    $script:List = [pscustomobject]@{
        version         = '7'
        recommendations = @(
            [pscustomobject]@{ id = 'SmartLockout'; standard = 'SmartLockout'; variables = [pscustomobject]@{ LockoutThreshold = 5 }; reason = 'Because.' }
            [pscustomobject]@{ id = 'NotInThisVersion'; standard = 'NotInThisVersion'; variables = [pscustomobject]@{} }
            [pscustomobject]@{ id = 'CA002'; standard = 'ConditionalAccessTemplate'; variables = [pscustomobject]@{ state = 'enabled' }; template = [pscustomobject]@{ repository = 'owner/repo'; path = 'CA002.json' } }
        )
    }
    $script:Drift = { [pscustomobject]@{ Compliant = $false; CurrentValue = [pscustomobject]@{ lockoutThreshold = 10; notify = 'soc@contoso.com' }; Diff = @([pscustomobject]@{ Property = 'lockoutThreshold'; ExpectedValue = 5; ReceivedValue = 10 }) } }
}

Describe 'Get-CIPPBaselineStandardGrade' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Invoke-CIPPBaselineStandard $script:Drift
    }

    It 'compares with the values it is given' {
        $Grade = Get-CIPPBaselineStandardGrade -TenantFilter 'contoso.com' -Standard 'SmartLockout' -Variables ([pscustomobject]@{ LockoutThreshold = 5 })

        $Grade.Status | Should -Be 'Drift'
        Should -Invoke Invoke-CIPPBaselineStandard -Times 1 -Exactly -ParameterFilter { $GradeOnly -and $Mode -eq 'compare' -and $Item.Variables.LockoutThreshold -eq 5 }
    }

    It 'does not read the tenant for a template family without a template' {
        Mock Get-CIPPBaselineDefinition { $script:Family }

        (Get-CIPPBaselineStandardGrade -TenantFilter 'contoso.com' -Standard 'ConditionalAccessTemplate').Status | Should -Be 'Needs a choice'
        Should -Invoke Invoke-CIPPBaselineStandard -Times 0 -Exactly
    }

    It 'compares a template family once it is given its template' {
        Mock Get-CIPPBaselineDefinition { $script:Family }

        (Get-CIPPBaselineStandardGrade -TenantFilter 'contoso.com' -Standard 'ConditionalAccessTemplate' -Variables ([pscustomobject]@{ caTemplate = 'tpl-1'; state = 'enabled' })).Status | Should -Be 'Drift'
        Should -Invoke Invoke-CIPPBaselineStandard -Times 1 -Exactly -ParameterFilter { $Item.Variables.caTemplate -eq 'tpl-1' }
    }
}

Describe 'Push-CIPPManagedBaselineRecommendationCollect' {
    BeforeEach {
        $script:Written = $null
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
        Mock Update-CippQueueEntry {}
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Invoke-CIPPBaselineStandard $script:Drift
        $script:Item = @{ Partition = 'tenant-1'; ScanId = 'scan-2'; TenantFilter = 'contoso.com'; Id = 'SmartLockout'; Standard = 'SmartLockout'; Variables = [pscustomobject]@{ LockoutThreshold = 5 }; Reason = 'Because.'; InBaseline = $false; FirstSeen = 0 }
    }

    It 'stores a difference as a recommendation, with the value as it is' {
        Push-CIPPManagedBaselineRecommendationCollect -Item $script:Item

        $script:Written.PartitionKey | Should -Be 'tenant-1'
        $script:Written.RowKey | Should -Be 'rec-SmartLockout'
        $script:Written.Status | Should -Be 'Recommended'
        $script:Written.ScanId | Should -Be 'scan-2'
        $script:Written.Current | Should -BeLike '*soc@contoso.com*'
        ($script:Written.Differences | ConvertFrom-Json)[0].ExpectedValue | Should -Be 5
        ($script:Written.Variables | ConvertFrom-Json).LockoutThreshold | Should -Be 5
        $script:Written.FirstSeen | Should -BeGreaterThan 0
    }

    It 'keeps the date a finding was first seen' {
        $script:Item.FirstSeen = 1700000000

        Push-CIPPManagedBaselineRecommendationCollect -Item $script:Item

        $script:Written.FirstSeen | Should -Be 1700000000
    }

    It 'marks a difference a baseline already holds as covered' {
        $script:Item.InBaseline = $true

        Push-CIPPManagedBaselineRecommendationCollect -Item $script:Item

        $script:Written.Status | Should -Be 'Covered by a baseline'
    }

    It 'stores <Expected> when the compare returns <Case>' -ForEach @(
        @{ Case = 'a compliant value'; Expected = 'Compliant'; Graded = { [pscustomobject]@{ Compliant = $true; CurrentValue = [pscustomobject]@{ lockoutThreshold = 5 }; Diff = @() } } }
        @{ Case = 'a missing licence'; Expected = 'No licence'; Graded = { [pscustomobject]@{ Outcome = 'Skipped'; Status = 'Skipped - No License' } } }
        @{ Case = 'nothing'; Expected = 'No data'; Graded = { $null } }
        @{ Case = 'an error'; Expected = 'No data'; Graded = { throw 'boom' } }
    ) {
        Mock Invoke-CIPPBaselineStandard $Graded

        Push-CIPPManagedBaselineRecommendationCollect -Item $script:Item

        $script:Written.Status | Should -Be $Expected
        $script:Written.FirstSeen | Should -Be 0
    }
}

Describe 'Start-CIPPManagedBaselineRecommendationScan' {
    BeforeEach {
        $script:Existing = @()
        $script:Entities = [System.Collections.Generic.List[object]]::new()
        $script:Started = $null
        Mock Get-CIPPAzDataTableEntity { @($script:Existing) }
        Mock Add-CIPPAzDataTableEntity { $script:Entities.Add($Entity) }
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Invoke-ManagedBaselinesRequest { $script:List }
        Mock Get-CIPPBaselineDefinition { $script:Definition; $script:Family }
        Mock Get-CIPPBaselineWorkItems { @() }
        Mock Start-CIPPOrchestrator { $script:Started = $InputObject }
    }

    It 'queues one compare per entry of the list that this CIPP knows, with the values from the list' {
        $Result = Start-CIPPManagedBaselineRecommendationScan -Tenant $script:Tenant -StartedBy 'admin@partner.example'

        $Result.Total | Should -Be 1
        @($script:Started.Batch).Count | Should -Be 1
        $script:Started.Batch[0].FunctionName | Should -Be 'CIPPManagedBaselineRecommendationCollect'
        $script:Started.Batch[0].Variables.LockoutThreshold | Should -Be 5
        $script:Started.PostExecution.FunctionName | Should -Be 'CIPPManagedBaselineRecommendationComplete'
        $Scan = $script:Entities.Where({ $_.RowKey -eq 'scan' -and $_.Status -eq 'Running' })[0]
        $Scan.ListVersion | Should -Be '7'
        $Scan.Total | Should -Be 1
        # One standard this CIPP does not know, one Conditional Access template.
        $Scan.Skipped | Should -Be 2
        $Scan.StartedBy | Should -Be 'admin@partner.example'
    }

    It 'leaves Conditional Access out and reads no template library' {
        $null = Start-CIPPManagedBaselineRecommendationScan -Tenant $script:Tenant

        @($script:Started.Batch).Where({ $_.Standard -eq 'ConditionalAccessTemplate' }).Count | Should -Be 0
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Context -eq 'templates' }
    }

    It 'marks a standard that an assigned baseline already holds as covered' {
        Mock Get-CIPPBaselineWorkItems { [pscustomobject]@{ BaseName = 'SmartLockout' } }

        $null = Start-CIPPManagedBaselineRecommendationScan -Tenant $script:Tenant

        $script:Started.Batch[0].InBaseline | Should -BeTrue
    }

    It 'starts nothing when the service gives no list' {
        Mock Invoke-ManagedBaselinesRequest { throw [System.UnauthorizedAccessException]::new('CyberDrain rejected the API key.') }

        { Start-CIPPManagedBaselineRecommendationScan -Tenant $script:Tenant } | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        $script:Entities.Count | Should -Be 0
    }

    It 'refuses a tenant that is still being scanned' {
        $script:Existing = @([pscustomobject]@{ RowKey = 'scan'; Status = 'Running'; StartedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 60 })

        { Start-CIPPManagedBaselineRecommendationScan -Tenant $script:Tenant } | Should -Throw '*still running*'
    }

    It 'hands the first-seen date of an open finding to the next scan' {
        $script:Existing = @(
            [pscustomobject]@{ RowKey = 'scan'; Status = 'Finished'; StartedAt = 100; FinishedAt = 200 }
            [pscustomobject]@{ RowKey = 'rec-SmartLockout'; Status = 'Recommended'; FirstSeen = 1700000000 }
        )

        $null = Start-CIPPManagedBaselineRecommendationScan -Tenant $script:Tenant

        $script:Started.Batch[0].FirstSeen | Should -Be 1700000000
        $Scan = $script:Entities.Where({ $_.RowKey -eq 'scan' -and $_.Status -eq 'Running' })[0]
        $Scan.HadPrevious | Should -BeTrue
        $Scan.PreviousFindings | Should -BeLike '*rec-SmartLockout*'
    }
}

Describe 'Complete-CIPPManagedBaselineRecommendationScan' {
    BeforeEach {
        $script:Removed = @()
        $script:Totals = $null
        Mock Remove-CIPPAzDataTableEntity { $script:Removed = @($Entity) }
        Mock Add-CIPPAzDataTableEntity { $script:Totals = $Entity }
        Mock Get-CIPPAzDataTableEntity {
            @(
                [pscustomobject]@{ PartitionKey = 'tenant-1'; RowKey = 'scan'; ScanId = 'scan-2'; HadPrevious = $true; PreviousFindings = '["rec-Old","rec-Kept"]' }
                [pscustomobject]@{ PartitionKey = 'tenant-1'; RowKey = 'rec-Old'; ScanId = 'scan-1'; Status = 'Recommended' }
                [pscustomobject]@{ PartitionKey = 'tenant-1'; RowKey = 'rec-Kept'; ScanId = 'scan-2'; Status = 'Recommended' }
                [pscustomobject]@{ PartitionKey = 'tenant-1'; RowKey = 'rec-New'; ScanId = 'scan-2'; Status = 'Covered by a baseline' }
                [pscustomobject]@{ PartitionKey = 'tenant-1'; RowKey = 'rec-Fine'; ScanId = 'scan-2'; Status = 'Compliant' }
            )
        }
    }

    It 'removes what the scan no longer found and counts new and resolved findings' {
        Complete-CIPPManagedBaselineRecommendationScan -Partition 'tenant-1' -ScanId 'scan-2'

        @($script:Removed.RowKey) | Should -Be @('rec-Old')
        $script:Totals.Status | Should -Be 'Finished'
        $script:Totals.Recommended | Should -Be 1
        $script:Totals.Covered | Should -Be 1
        $script:Totals.Compliant | Should -Be 1
        $script:Totals.NewFindings | Should -Be 1
        $script:Totals.ResolvedFindings | Should -Be 1
    }

    It 'leaves a tenant alone when a newer scan has started' {
        Complete-CIPPManagedBaselineRecommendationScan -Partition 'tenant-1' -ScanId 'scan-1'

        $script:Removed.Count | Should -Be 0
        $script:Totals | Should -BeNullOrEmpty
    }
}

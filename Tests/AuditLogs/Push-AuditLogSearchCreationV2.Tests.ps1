# Push-AuditLogDownloadV2 re-plans failed searches (MANUAL-* included) and only this function
# re-creates them, so the ledger read must cover the whole partition.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogSearchCreationV2.ps1')

    function Get-CippTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, $OperationType) }
    function Get-CippAuditLogPlannedWindows { param($ExistingRows, $Now) }
    function Get-CippAuditLogReconciliationWindows { param($ExistingRows, $Now) }
    function Get-CippAuditLogNextAttempt { param($Attempts) }
    function New-CippAuditLogSearchV2 { param($TenantFilter, $StartTime, $EndTime) }
}

Describe 'Push-AuditLogSearchCreationV2 ledger read' {
    BeforeEach {
        $script:Reads = [System.Collections.Generic.List[object]]::new()
        $script:Searched = [System.Collections.Generic.List[object]]::new()
        $Start = (Get-Date).ToUniversalTime().AddDays(-2)

        Mock Get-CippTable { @{ Context = 'ledger' } }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-CIPPAzDataTableEntity {
            $script:Reads.Add([pscustomobject]@{ Filter = $Filter; Property = $Property })
            [pscustomobject]@{ RowKey = 'MANUAL-0a1b'; State = 'Planned'; WindowStart = $Start; WindowEnd = $Start.AddHours(6) }
        }
        Mock New-CippAuditLogSearchV2 {
            $script:Searched.Add($StartTime)
            [pscustomobject]@{ Outcome = 'Created'; Id = 'search-1'; Status = 'notStarted' }
        }
    }

    It 're-creates a search for a re-planned manual row' {
        Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.onmicrosoft.com'; TenantId = 't' } | Should -BeTrue
        $script:Searched.Count | Should -Be 1
    }

    It 'reads the whole partition in one query without split-entity markers' {
        Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = "o'brien.onmicrosoft.com"; TenantId = 't' } | Out-Null
        $script:Reads.Count | Should -Be 1
        $script:Reads[0].Filter | Should -Be "PartitionKey eq 'o''brien.onmicrosoft.com'"
        $script:Reads[0].Property | Should -Not -Contain 'OriginalEntityId'
        $script:Reads[0].Property | Should -Contain 'WindowEnd'
    }
}

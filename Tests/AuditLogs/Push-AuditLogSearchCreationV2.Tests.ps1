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
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
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

Describe 'Push-AuditLogSearchCreationV2 missing permissions' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $Start = (Get-Date).ToUniversalTime().AddHours(-3)

        Mock Get-CippTable { @{ Context = ($TableName -eq 'AuditLogDisabledTenants' ? 'disabled' : 'ledger') } }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add([pscustomobject]@{ Context = $Context; Entity = $Entity }) }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ RowKey = '20261013030000'; State = 'Planned'; WindowStart = $Start; WindowEnd = $Start.AddMinutes(35) }
            [pscustomobject]@{ RowKey = '20261013033500'; State = 'Planned'; WindowStart = $Start.AddMinutes(35); WindowEnd = $Start.AddMinutes(70) }
        }
        Mock Get-CippAuditLogNextAttempt { (Get-Date).ToUniversalTime().AddMinutes(5) }
        Mock Write-LogMessage {}
        Mock New-CippAuditLogSearchV2 {
            [pscustomobject]@{ Outcome = 'AccessDenied'; Status = 'MissingPermissions'; Message = 'no audit permission'; Throttled = $false }
        }
    }

    It 'stops after the first window, disables the tenant for 24 hours and logs it once' {
        Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.onmicrosoft.com'; TenantId = 't' } | Should -BeTrue

        Should -Invoke New-CippAuditLogSearchV2 -Times 1 -Exactly
        $Disabled = @($script:Writes | Where-Object { $_.Context -eq 'disabled' })
        $Disabled.Count | Should -Be 1
        $Disabled[0].Entity.Status | Should -Be 'MissingPermissions'
        $Disabled[0].Entity.ExpiresAtUnix | Should -BeGreaterThan ([datetimeoffset]::UtcNow.AddHours(23).ToUnixTimeSeconds())
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $tenant -eq 'contoso.onmicrosoft.com' -and $message -like '*no audit permission*' }
    }
}

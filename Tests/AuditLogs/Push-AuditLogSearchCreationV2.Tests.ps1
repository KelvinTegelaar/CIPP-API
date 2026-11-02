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
    function New-CippAuditLogSearchV2 { param($Searches) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    function New-Outcome {
        param($Search, $Outcome = 'Created', $Status = 'notStarted', [switch]$Throttled, $Message)
        [pscustomobject]@{ TenantFilter = $Search.TenantFilter; RowKey = $Search.RowKey; Id = $(if ($Outcome -eq 'Created') { "search-$($Search.RowKey)" }); Status = $Status; Outcome = $Outcome; Message = $Message; Throttled = [bool]$Throttled }
    }
}

Describe 'Push-AuditLogSearchCreationV2' {
    BeforeEach {
        $script:Reads = [System.Collections.Generic.List[object]]::new()
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Sent = [System.Collections.Generic.List[object]]::new()
        $script:Start = (Get-Date).ToUniversalTime().AddHours(-3)

        Mock Get-CippTable { @{ Context = ($TableName -eq 'AuditLogDisabledTenants' ? 'disabled' : 'ledger') } }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add([pscustomobject]@{ Context = $Context; Entity = @($Entity); OperationType = $OperationType }) }
        Mock Get-CIPPAzDataTableEntity {
            $script:Reads.Add([pscustomobject]@{ Filter = $Filter; Property = $Property })
            [pscustomobject]@{ RowKey = 'MANUAL-0a1b'; State = 'Planned'; WindowStart = $script:Start; WindowEnd = $script:Start.AddHours(1) }
        }
        Mock Get-CippAuditLogPlannedWindows {
            [pscustomobject]@{ RowKey = '20261013033500'; WindowStart = $script:Start.AddMinutes(35); WindowEnd = $script:Start.AddMinutes(70) }
        }
        Mock Get-CippAuditLogReconciliationWindows { }
        Mock Get-CippAuditLogNextAttempt { (Get-Date).ToUniversalTime().AddMinutes(5) }
        Mock Write-LogMessage {}
        Mock New-CippAuditLogSearchV2 {
            foreach ($Search in $Searches) { $script:Sent.Add($Search); New-Outcome $Search }
        }
    }

    It 'creates every tenant''s due windows in one call' {
        $Item = @{ Tenants = @(@{ TenantFilter = 'a.com'; TenantId = '1' }, @{ TenantFilter = 'b.com'; TenantId = '2' }) }
        Push-AuditLogSearchCreationV2 -Item $Item | Should -BeTrue

        Should -Invoke New-CippAuditLogSearchV2 -Times 1 -Exactly
        $script:Sent.Count | Should -Be 4
        # The freshest regular window goes first; the re-planned manual row follows.
        @($script:Sent | Where-Object TenantFilter -EQ 'a.com').RowKey | Should -Be @('20261013033500', 'MANUAL-0a1b')
    }

    It 'writes each tenant''s rows once, with the new window inserted as Created' {
        Push-AuditLogSearchCreationV2 -Item @{ Tenants = @(@{ TenantFilter = 'a.com'; TenantId = '1' }) } | Out-Null

        $script:Writes.Count | Should -Be 1
        $script:Writes[0].OperationType | Should -Be 'UpsertMerge'
        $New = $script:Writes[0].Entity | Where-Object RowKey -EQ '20261013033500'
        $New.State | Should -Be 'Created'
        $New.SearchId | Should -Be 'search-20261013033500'
        $New.TenantId | Should -Be '1'
        $New.Type | Should -Be 'Window'
        ($script:Writes[0].Entity | Where-Object RowKey -EQ 'MANUAL-0a1b').State | Should -Be 'Created'
    }

    It 'still accepts a single-tenant item queued before chunking' {
        Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.onmicrosoft.com'; TenantId = 't' } | Should -BeTrue
        $script:Sent.Count | Should -Be 2
    }

    It 'reads the whole partition in one query without split-entity markers' {
        Push-AuditLogSearchCreationV2 -Item @{ Tenants = @(@{ TenantFilter = "o'brien.onmicrosoft.com"; TenantId = 't' }) } | Out-Null
        $script:Reads.Count | Should -Be 1
        $script:Reads[0].Filter | Should -Be "PartitionKey eq 'o''brien.onmicrosoft.com'"
        $script:Reads[0].Property | Should -Not -Contain 'OriginalEntityId'
        $script:Reads[0].Property | Should -Contain 'WindowEnd'
    }

    It 'keeps a throttled window Planned without counting an attempt' {
        Mock New-CippAuditLogSearchV2 { foreach ($Search in $Searches) { New-Outcome $Search -Outcome 'Transient' -Status 'TooManyRequests' -Throttled } }
        Push-AuditLogSearchCreationV2 -Item @{ Tenants = @(@{ TenantFilter = 'a.com'; TenantId = '1' }) } | Out-Null

        $Row = $script:Writes[0].Entity | Where-Object RowKey -EQ 'MANUAL-0a1b'
        $Row.State | Should -Be 'Planned'
        $Row.ThrottleCount | Should -Be 1
        $Row.ContainsKey('Attempts') | Should -BeFalse
    }

    It 'dead-letters a window that keeps failing' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'MANUAL-0a1b'; State = 'Planned'; WindowStart = $script:Start; WindowEnd = $script:Start.AddHours(1); Attempts = 7 } }
        Mock Get-CippAuditLogPlannedWindows { }
        Mock New-CippAuditLogSearchV2 { foreach ($Search in $Searches) { New-Outcome $Search -Outcome 'Transient' -Status 'UnknownError' -Message 'oops' } }
        Push-AuditLogSearchCreationV2 -Item @{ Tenants = @(@{ TenantFilter = 'a.com'; TenantId = '1' }) } | Out-Null

        ($script:Writes[0].Entity | Where-Object RowKey -EQ 'MANUAL-0a1b').State | Should -Be 'DeadLetter'
    }

    It 'disables a tenant without audit permissions for 24 hours and logs it once' {
        Mock New-CippAuditLogSearchV2 {
            foreach ($Search in $Searches) {
                if ($Search.TenantFilter -eq 'denied.com') { New-Outcome $Search -Outcome 'AccessDenied' -Status 'MissingPermissions' -Message 'no audit permission' } else { New-Outcome $Search }
            }
        }
        $Item = @{ Tenants = @(@{ TenantFilter = 'denied.com'; TenantId = '1' }, @{ TenantFilter = 'fine.com'; TenantId = '2' }) }
        Push-AuditLogSearchCreationV2 -Item $Item | Should -BeTrue

        $Disabled = @($script:Writes | Where-Object { $_.Context -eq 'disabled' })
        $Disabled.Count | Should -Be 1
        $Disabled[0].Entity[0].RowKey | Should -Be 'denied.com'
        $Disabled[0].Entity[0].Status | Should -Be 'MissingPermissions'
        $Disabled[0].Entity[0].ExpiresAtUnix | Should -BeGreaterThan ([datetimeoffset]::UtcNow.AddHours(23).ToUnixTimeSeconds())
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $tenant -eq 'denied.com' -and $message -like '*no audit permission*' }
        $Fine = $script:Writes | Where-Object { $_.Context -eq 'ledger' -and $_.Entity[0].PartitionKey -eq 'fine.com' }
        @($Fine.Entity.State | Select-Object -Unique) | Should -Be @('Created')
    }

    It 'keeps planning the other tenants when one ledger read fails' {
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*broken.com*") { throw 'table unavailable' }
            [pscustomobject]@{ RowKey = 'MANUAL-0a1b'; State = 'Planned'; WindowStart = $script:Start; WindowEnd = $script:Start.AddHours(1) }
        }
        Push-AuditLogSearchCreationV2 -Item @{ Tenants = @(@{ TenantFilter = 'broken.com' }, @{ TenantFilter = 'fine.com' }) } | Should -BeTrue
        @($script:Sent.TenantFilter | Select-Object -Unique) | Should -Be @('fine.com')
    }
}

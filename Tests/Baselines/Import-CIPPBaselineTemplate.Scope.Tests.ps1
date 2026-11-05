# A community baseline import replaces the baseline's assignments with the file's, so a tenant-restricted
# caller may only import it when both the file's and the existing baseline's tenants are in their access.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) $script:Existing }
    function New-CIPPBaseline { param($Baseline, $User, $Source, $SHA, $SourcePath, [switch]$LocalChanges) [pscustomobject]@{ DeltaCount = 0 } }
    function Get-TenantGroups { @() }
    function Get-CIPPTenantLookup { @{ 'mine.com' = @{ customerId = 'tenant-1' }; 'victim.com' = @{ customerId = 'tenant-2' } } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineOutOfScopeAssignment.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines/Import-CIPPBaselineTemplate.ps1')

    function Import-Baseline($Assigned) {
        $Baseline = [pscustomobject]@{ templateName = 'Hardening'; assignedTenants = @($Assigned); stages = @() }
        Import-CIPPBaselineTemplate -Baseline $Baseline -FullName 'owner/repo' -Branch 'main' -SHA 'new' -Path 'b.json'
    }
}

Describe 'Import-CIPPBaselineTemplate tenant scope' {
    BeforeEach {
        $script:Existing = $null
        $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
        $script:CippAllowedTenantsStorage.Value = @('tenant-1')
        Mock New-CIPPBaseline { [pscustomobject]@{ DeltaCount = 0 } }
    }
    AfterAll { $script:CippAllowedTenantsStorage = $null }

    It 'refuses a file assigned to a tenant outside the caller''s access' {
        { Import-Baseline @{ value = 'victim.com'; label = 'Victim' } } | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'refuses an update to a baseline assigned outside the caller''s access' {
        $script:Existing = [pscustomobject]@{ RowKey = 'b1'; templateName = 'Hardening'; SHA = 'old'; assignedTo = '[{"value":"victim.com","label":"Victim"}]' }
        { Import-Baseline @{ value = 'Exported Template' } } | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'imports the placeholder or the caller''s own tenants' {
        $null = Import-Baseline @(@{ value = 'Exported Template' }, @{ value = 'mine.com' })
        Should -Invoke New-CIPPBaseline -Times 1
    }

    It 'keeps the file''s assignments for an unrestricted caller' {
        $script:CippAllowedTenantsStorage.Value = $null
        $null = Import-Baseline @{ value = 'victim.com' }
        Should -Invoke New-CIPPBaseline -Times 1 -ParameterFilter { $Baseline.assignedTenants.value -eq 'victim.com' }
    }
}

# The baseline list page needs the same Imported/UpdateAvailable signal listStandardTemplates
# already shows for standards templates: source (repo FullName) and isSynced (has a SHA).

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = "stub-$tablename" } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-Tenants { @() }
    function Get-TenantGroups { @() }
    function Write-LogMessage { param($API, $message, $Sev) }
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
    function Get-CIPPTemplateSourceUrl { param($Source, $SourcePath, $Repos) if ($Source) { "https://github.com/$Source" } }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaseline.ps1')
}

Describe 'Get-CIPPBaseline source/isSynced projection' {
    BeforeEach {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @(
                    [pscustomobject]@{
                        RowKey       = 'baseline-1'
                        templateName = 'Imported Baseline'
                        Stages       = '[]'
                        Source       = 'Org/repo'
                        SHA          = 'abc123'
                    }
                )
            } else {
                @()
            }
        }
    }

    It 'exposes source and isSynced true when the rollout row carries repo provenance' {
        $Result = Get-CIPPBaseline -ID 'baseline-1'
        $Result.source | Should -Be 'Org/repo'
        $Result.isSynced | Should -BeTrue
        $Result.sourceUrl | Should -Be 'https://github.com/Org/repo'
    }

    It 'exposes isSynced false when the rollout row has no SHA' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @([pscustomobject]@{ RowKey = 'baseline-2'; templateName = 'Local Baseline'; Stages = '[]' })
            } else {
                @()
            }
        }
        $Result = Get-CIPPBaseline -ID 'baseline-2'
        $Result.isSynced | Should -BeFalse
        $Result.source | Should -BeNullOrEmpty
    }

    It 'exposes hasLocalChanges true when the rollout row is synced and flagged' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @([pscustomobject]@{ RowKey = 'baseline-3'; templateName = 'Edited Baseline'; Stages = '[]'; Source = 'Org/repo'; SHA = 'abc123'; LocalChanges = $true })
            } else {
                @()
            }
        }
        $Result = Get-CIPPBaseline -ID 'baseline-3'
        $Result.hasLocalChanges | Should -BeTrue
    }

    It 'exposes hasLocalChanges false when the rollout row is synced and unflagged' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @([pscustomobject]@{ RowKey = 'baseline-4'; templateName = 'Pushed Baseline'; Stages = '[]'; Source = 'Org/repo'; SHA = 'abc123'; LocalChanges = $false })
            } else {
                @()
            }
        }
        $Result = Get-CIPPBaseline -ID 'baseline-4'
        $Result.hasLocalChanges | Should -BeFalse
    }

    It 'exposes hasLocalChanges $null when the rollout row has no Source' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @([pscustomobject]@{ RowKey = 'baseline-5'; templateName = 'Local Baseline'; Stages = '[]' })
            } else {
                @()
            }
        }
        $Result = Get-CIPPBaseline -ID 'baseline-5'
        $Result.hasLocalChanges | Should -BeNullOrEmpty
    }

    It 'does not read the baseline migration marker as a repo sync' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @([pscustomobject]@{ RowKey = 'baseline-5'; templateName = 'Migrated Baseline'; Stages = '[]'; Source = 'StandardsTemplateV2:9c4c44c0-7e0d-4e5d-a018-dd64619c49bc'; SHA = 'abc123' })
            } else {
                @()
            }
        }
        $Result = Get-CIPPBaseline -ID 'baseline-5'
        $Result.source | Should -BeNullOrEmpty
        $Result.isSynced | Should -BeFalse
        $Result.sourceUrl | Should -BeNullOrEmpty
        $Result.hasLocalChanges | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaseline excluded tenant group expansion' {
    BeforeEach {
        Mock -CommandName Get-TenantGroups -MockWith {
            @(
                [pscustomobject]@{
                    Id      = 'group-guid-1'
                    Name    = 'Group A'
                    Members = @(
                        [pscustomobject]@{ defaultDomainName = 'tenant1.onmicrosoft.com' }
                        [pscustomobject]@{ defaultDomainName = 'tenant4.onmicrosoft.com' }
                    )
                }
            )
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -like "*PartitionKey eq 'rollout'*") {
                @(
                    [pscustomobject]@{
                        RowKey          = 'baseline-6'
                        templateName    = 'Group Exclusion Baseline'
                        Stages          = '[{"name":"Stage 1","logic":"and","conditions":[]}]'
                        excludedTenants = '["group-guid-1","tenant5.onmicrosoft.com"]'
                        excludedTo      = '[{"label":"Group A (group-guid-1)","value":"group-guid-1","type":"Group"},{"label":"tenant5.onmicrosoft.com","value":"tenant5.onmicrosoft.com","type":"Tenant"}]'
                    }
                )
            } elseif ($Filter -like "*standardItem*") {
                @(
                    [pscustomobject]@{ scope = 'group'; scopeId = 'group-guid-1'; scopeName = 'Group A'; stage = 1; standardName = 'Standard1#1'; expectedValue = '{}'; remediateEnabled = $true }
                    [pscustomobject]@{ scope = 'tenant'; scopeId = 'tenant5.onmicrosoft.com'; scopeName = 'tenant5.onmicrosoft.com'; stage = 1; standardName = 'Standard1#1'; expectedValue = '{}'; remediateEnabled = $true }
                    [pscustomobject]@{ scope = 'tenant'; scopeId = 'tenant6.onmicrosoft.com'; scopeName = 'tenant6.onmicrosoft.com'; stage = 1; standardName = 'Standard1#1'; expectedValue = '{}'; remediateEnabled = $true }
                )
            } else {
                @()
            }
        }
    }

    It 'expands an excluded group Id to its member domains and keeps plain domains' {
        $Result = Get-CIPPBaseline -ID 'baseline-6'
        $Result.excludedTenants | Should -Contain 'tenant1.onmicrosoft.com'
        $Result.excludedTenants | Should -Contain 'tenant4.onmicrosoft.com'
        $Result.excludedTenants | Should -Contain 'tenant5.onmicrosoft.com'
        $Result.excludedTenants | Should -Not -Contain 'group-guid-1'
    }

    It 'keeps the raw group entry in exclusions for display instead of its members' {
        $Result = Get-CIPPBaseline -ID 'baseline-6'
        $GroupExclusion = $Result.exclusions | Where-Object { $_.type -eq 'Group' }
        $GroupExclusion.value | Should -Be 'group-guid-1'
        ($Result.exclusions | Where-Object { $_.value -eq 'tenant1.onmicrosoft.com' }) | Should -BeNullOrEmpty
    }

    It 'excludes tenants assigned via group membership from tenant states' {
        $Result = Get-CIPPBaseline -ID 'baseline-6'
        $Result.tenantStates.tenantFilter | Should -Not -Contain 'tenant1.onmicrosoft.com'
        $Result.tenantStates.tenantFilter | Should -Not -Contain 'tenant4.onmicrosoft.com'
        $Result.tenantStates.tenantFilter | Should -Not -Contain 'tenant5.onmicrosoft.com'
        $Result.tenantStates.tenantFilter | Should -Contain 'tenant6.onmicrosoft.com'
    }
}

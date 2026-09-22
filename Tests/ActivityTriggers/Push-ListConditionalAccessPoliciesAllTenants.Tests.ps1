# Cache writes for cacheCAPolicies must be idempotent: rows used to be keyed by a fresh
# GUID per policy per run with no cleanup, so overlapping fan-outs (a request near the
# 60-minute staleness boundary queues a second run while the first is filling) doubled
# every policy in the table and the list endpoint served the duplicates.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ListConditionalAccessPoliciesAllTenants.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-ListConditionalAccessPoliciesAllTenants.ps1 under Modules/' }

    # Stubs so Mock has commands to replace.
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPTable { param($TableName) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp) }

    . $FunctionPath

    function New-BulkResult {
        param([object[]]$Policies)
        @(
            [pscustomobject]@{ id = 'policies'; body = [pscustomobject]@{ value = $Policies } }
            foreach ($Id in 'namedLocations', 'applications', 'roleDefinitions', 'groups', 'users', 'servicePrincipals') {
                [pscustomobject]@{ id = $Id; body = [pscustomobject]@{ value = @() } }
            }
        )
    }
}

Describe 'Push-ListConditionalAccessPoliciesAllTenants cache idempotence' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ defaultDomainName = 'contoso.com' } }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'fake' } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written.Add(@{ Entity = $Entity; Force = [bool]$Force }) }
    }

    It 'writes deterministic tenant+policy RowKeys, identical across runs, with -Force' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            New-BulkResult -Policies @(
                [pscustomobject]@{ id = 'p1'; displayName = 'Block legacy auth'; state = 'enabled'; conditions = $null; grantControls = $null }
                [pscustomobject]@{ id = 'p2'; displayName = 'Require MFA'; state = 'enabled'; conditions = $null; grantControls = $null }
            )
        }

        Push-ListConditionalAccessPoliciesAllTenants -Item ([pscustomobject]@{ customerId = 'tenant-guid' })
        Push-ListConditionalAccessPoliciesAllTenants -Item ([pscustomobject]@{ customerId = 'tenant-guid' })

        $script:Written | Should -HaveCount 4
        # Same keys both runs: the second run upserts instead of appending duplicates.
        ($script:Written.Entity.RowKey | Sort-Object -Unique) | Should -Be @('contoso.com-p1', 'contoso.com-p2')
        $script:Written.Force | Should -Not -Contain $false
        ($script:Written.Entity.Policy[0] | ConvertFrom-Json).id | Should -Be 'p1'
    }

    It 'writes one deterministic error row per tenant when the tenant is unreachable' {
        Mock -CommandName New-GraphBulkRequest -MockWith { throw 'tenant unreachable' }

        Push-ListConditionalAccessPoliciesAllTenants -Item ([pscustomobject]@{ customerId = 'tenant-guid' })
        Push-ListConditionalAccessPoliciesAllTenants -Item ([pscustomobject]@{ customerId = 'tenant-guid' })

        $script:Written | Should -HaveCount 2
        ($script:Written.Entity.RowKey | Sort-Object -Unique) | Should -Be @('contoso.com-Error')
        ($script:Written.Entity.Policy[0] | ConvertFrom-Json).state | Should -Be 'Error'
    }
}

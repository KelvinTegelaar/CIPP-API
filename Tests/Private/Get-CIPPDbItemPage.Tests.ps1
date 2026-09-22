# Pester tests for Get-CIPPDbItemPage
# Validates the reporting-database partition plan (count-row enumeration intersected with
# managed tenants, alphabetical), the single-tenant plan, the RowKey range handed to the
# walker, and count-marker removal.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stub every helper the function calls so Pester's Mock has a command to replace.
    function Get-CippTable { param($tablename) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPPagedTableRows {
        param($Table, $PartitionKeys, $RowKeyGe, $RowKeyLt, $ExtraFilterClauses, $PageSize, $MaxQueries, $ContinuationToken)
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDbItemPage.ps1')
}

Describe 'Get-CIPPDbItemPage' {
    BeforeEach {
        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'fake' } }
        Mock -CommandName Get-CIPPDbItem -MockWith { @() }
        Mock -CommandName Get-CIPPPagedTableRows -MockWith {
            [PSCustomObject]@{
                Rows      = [System.Collections.Generic.List[object]]@(
                    [PSCustomObject]@{ PartitionKey = 'alpha.onmicrosoft.com'; RowKey = 'Guests-1'; Data = '{}' }
                    [PSCustomObject]@{ PartitionKey = 'alpha.onmicrosoft.com'; RowKey = 'Guests-Count'; DataCount = 1 }
                )
                NextToken = 'alpha.onmicrosoft.com|Guests-Count'
            }
        }
    }

    It 'builds the AllTenants plan from count rows, managed tenants only, alphabetical' {
        Mock -CommandName Get-CIPPDbItem -MockWith {
            @(
                [PSCustomObject]@{ PartitionKey = 'zeta.onmicrosoft.com'; RowKey = 'Guests-Count'; DataCount = 5 }
                [PSCustomObject]@{ PartitionKey = 'alpha.onmicrosoft.com'; RowKey = 'Guests-Count'; DataCount = 2 }
                # Has cached data but is no longer managed - must be excluded from the walk.
                [PSCustomObject]@{ PartitionKey = 'gone.onmicrosoft.com'; RowKey = 'Guests-Count'; DataCount = 9 }
            )
        }
        Mock -CommandName Get-Tenants -MockWith {
            @(
                [PSCustomObject]@{ defaultDomainName = 'alpha.onmicrosoft.com' }
                [PSCustomObject]@{ defaultDomainName = 'zeta.onmicrosoft.com' }
            )
        }

        $Result = Get-CIPPDbItemPage -TenantFilter 'AllTenants' -Type 'Guests' -PageSize 500 -ContinuationToken 'tok'

        Should -Invoke Get-CIPPDbItem -Times 1 -ParameterFilter { $TenantFilter -eq 'allTenants' -and $Type -eq 'Guests' -and $CountsOnly }
        Should -Invoke Get-CIPPPagedTableRows -Times 1 -ParameterFilter {
            ($PartitionKeys -join ',') -eq 'alpha.onmicrosoft.com,zeta.onmicrosoft.com' -and
            $RowKeyGe -eq 'Guests-' -and $RowKeyLt -eq 'Guests.' -and
            $PageSize -eq 500 -and $ContinuationToken -eq 'tok'
        }
        # The count marker row is stripped; the data row and token pass through.
        $Result.Items | Should -HaveCount 1
        $Result.Items[0].RowKey | Should -Be 'Guests-1'
        $Result.NextToken | Should -Be 'alpha.onmicrosoft.com|Guests-Count'
    }

    It 'walks a single tenant partition after normalizing the tenant filter' {
        Mock -CommandName Get-Tenants -MockWith {
            [PSCustomObject]@{ defaultDomainName = 'alpha.onmicrosoft.com' }
        }

        $null = Get-CIPPDbItemPage -TenantFilter 'alpha.onmicrosoft.com' -Type 'Mailboxes'

        Should -Invoke Get-Tenants -Times 1 -ParameterFilter { $TenantFilter -eq 'alpha.onmicrosoft.com' }
        Should -Invoke Get-CIPPDbItem -Times 0
        Should -Invoke Get-CIPPPagedTableRows -Times 1 -ParameterFilter {
            ($PartitionKeys -join ',') -eq 'alpha.onmicrosoft.com' -and $RowKeyGe -eq 'Mailboxes-' -and $RowKeyLt -eq 'Mailboxes.'
        }
    }

    It 'throws when the single tenant cannot be resolved' {
        Mock -CommandName Get-Tenants -MockWith { $null }

        { Get-CIPPDbItemPage -TenantFilter 'missing.example.com' -Type 'Guests' } | Should -Throw "*not found*"
    }
}

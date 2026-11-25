# Pester tests for Save-CIPPOffboardingSnapshot: what is captured before offboarding strips it,
# and that the snapshot can never get in the way of the offboarding.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Get-CIPPLicenseSkuName { param($SkuIds, $TenantFilter) }
    function Get-CIPPPIMRoleAssignments { param($TenantFilter, $PrincipalId) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Write-Information { param($MessageData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Save-CIPPOffboardingSnapshot.ps1')
}

Describe 'Save-CIPPOffboardingSnapshot' {
    BeforeEach {
        $script:Entity = $null
        $script:Graph = @{
            user    = @{ status = 200; body = [pscustomobject]@{
                    id = 'u-1'; userPrincipalName = 'maria@contoso.com'; displayName = 'Maria Jensen'
                    assignedLicenses = @([pscustomobject]@{ skuId = 'sku-direct' }, [pscustomobject]@{ skuId = 'sku-group' })
                    licenseAssignmentStates = @(
                        [pscustomobject]@{ skuId = 'sku-direct'; assignedByGroup = $null; state = 'Active' }
                        [pscustomobject]@{ skuId = 'sku-group'; assignedByGroup = 'g-lic'; state = 'Active' }
                    )
                }
            }
            groups  = @{ status = 200; body = [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 'g-1'; displayName = 'Sales'; groupTypes = @(); mailEnabled = $false; securityEnabled = $true }
                        [pscustomobject]@{ id = 'g-2'; displayName = 'Team'; groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false }
                        [pscustomobject]@{ id = 'g-3'; displayName = 'DL'; groupTypes = @(); mailEnabled = $true; securityEnabled = $false }
                    )
                }
            }
            manager = @{ status = 200; body = [pscustomobject]@{ id = 'm-1'; userPrincipalName = 'boss@contoso.com'; displayName = 'The Boss' } }
            skus    = @{ status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ skuId = 'sku-direct'; skuPartNumber = 'SPE_E3' }) } }
        }
        Mock New-GraphBulkRequest { foreach ($Request in $Requests) { $Reply = $script:Graph[[string]$Request.id]; [pscustomobject]@{ id = $Request.id; status = $Reply.status; body = $Reply.body } } }
        Mock Get-CIPPLicenseSkuName { [pscustomobject]@{ skuId = 'sku-direct'; displayName = 'Microsoft 365 E3' } }
        Mock Get-CIPPPIMRoleAssignments {
            [pscustomobject]@{ RoleDefinitionId = 'role-1'; RoleDisplayName = 'Helpdesk Administrator'; MemberType = 'Direct' }
            [pscustomobject]@{ RoleDefinitionId = 'role-2'; RoleDisplayName = 'Inherited'; MemberType = 'Group' }
        }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-1' } }
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Get-CIPPAzDataTableEntity { }
        Mock Add-CIPPAzDataTableEntity { $script:Entity = $Entity }
        Mock Write-LogMessage { }
        Mock Write-Information { }
    }

    It 'writes the licences, groups, roles and manager keyed by customer id and user id' {
        Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' -Username 'maria@contoso.com' | Should -BeTrue

        $script:Entity.PartitionKey | Should -Be 'cust-1'
        $script:Entity.RowKey | Should -Be 'u-1'
        $script:Entity.UserPrincipalName | Should -Be 'maria@contoso.com'
        $script:Entity.DisplayName | Should -Be 'Maria Jensen'
        $script:Entity.OffboardedAt | Should -Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
        $Snapshot = $script:Entity.Snapshot | ConvertFrom-Json
        # The group-inherited licence comes back with its group, so only the direct one is recorded
        $Snapshot.Licenses.skuId | Should -Be @('sku-direct')
        $Snapshot.Licenses[0].skuPartNumber | Should -Be 'SPE_E3'
        $Snapshot.Licenses[0].displayName | Should -Be 'Microsoft 365 E3'
        $Snapshot.Groups.id | Should -Be @('g-1', 'g-2', 'g-3')
        $Snapshot.Groups.groupType | Should -Be @('Security', 'Microsoft 365', 'Distribution List')
        $Snapshot.Roles.id | Should -Be @('role-1')
        $Snapshot.Manager.id | Should -Be 'm-1'
    }

    It 'round-trips a snapshot with hundreds of groups as one JSON string' {
        $script:Graph.groups.body.value = @(1..600 | ForEach-Object { [pscustomobject]@{ id = [guid]::NewGuid().ToString(); displayName = "Group number $_ with a fairly long display name"; groupTypes = @(); mailEnabled = $false; securityEnabled = $true } })

        Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' | Should -BeTrue

        $script:Entity.Snapshot | Should -BeOfType [string]
        @(($script:Entity.Snapshot | ConvertFrom-Json).Groups).Count | Should -Be 600
    }

    It 'does not overwrite an existing snapshot with an empty one' {
        $script:Graph.user.body.assignedLicenses = @()
        $script:Graph.user.body.licenseAssignmentStates = @()
        $script:Graph.groups.body.value = @()
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'cust-1'; RowKey = 'u-1' } }

        Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' | Should -BeFalse

        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey eq 'cust-1' and RowKey eq 'u-1'" -and $Property -contains 'RowKey' }
    }

    It 'writes an empty snapshot when there is none yet' {
        $script:Graph.user.body.assignedLicenses = @()
        $script:Graph.groups.body.value = @()

        Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' | Should -BeTrue

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'replaces an existing snapshot when the user has groups or licences again' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'cust-1'; RowKey = 'u-1' } }

        Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' | Should -BeTrue

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'saves nothing when the group read fails, rather than recording no groups' {
        $script:Graph.groups = @{ status = 500; body = $null }

        Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' | Should -BeFalse

        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' }
    }

    It 'still saves licences and groups when the role read fails' {
        Mock Get-CIPPPIMRoleAssignments { throw 'PIM is unavailable' }

        Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' | Should -BeTrue

        @(($script:Entity.Snapshot | ConvertFrom-Json).Roles).Count | Should -Be 0
    }

    It 'logs a warning and does not throw when <Name> fails' -ForEach @(
        @{ Name = 'the Graph read'; Command = 'New-GraphBulkRequest' }
        @{ Name = 'the table write'; Command = 'Add-CIPPAzDataTableEntity' }
        @{ Name = 'the tenant lookup'; Command = 'Get-Tenants' }
    ) {
        Mock $Command { throw 'boom' }

        { Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' -Username 'maria@contoso.com' } | Should -Not -Throw
        Save-CIPPOffboardingSnapshot -TenantFilter 'contoso.com' -UserID 'u-1' -Username 'maria@contoso.com' | Should -BeFalse

        Should -Invoke Write-LogMessage -Times 2 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*maria@contoso.com*' }
    }
}

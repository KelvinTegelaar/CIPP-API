BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/TenantGroups/Update-CIPPDynamicTenantGroups.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/TenantGroups/Test-CIPPDynamicGroupFilter.ps1')

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity {
        param($TableName, $Filter)
        $script:Reads.Add($TableName)
        $script:Rows[$TableName]
    }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) if ($TableName -eq 'TenantGroupMembers') { $script:Added.Add($Entity.RowKey) } }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Removed.Add($Entity.RowKey) }
    function Get-Tenants { param([switch]$IncludeErrors) $script:Tenants }
    function New-GraphGetRequest { param($uri, $TenantId) $script:Fetches.Add($TenantId); if ($TenantId -in $script:FailFetch) { throw 'no token' }; @([pscustomobject]@{ skuId = 'bbbbbbbb-0000-0000-0000-000000000000' }) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-TenantGroups { param([switch]$SkipCache) }
    function Clear-CippAccessScopeCache {}
    function Get-NormalizedError { param($Message) $Message }
    function Get-CippException { param($Exception) $Exception }
    function Get-CIPPTenantCapabilities {
        param($TenantFilter)
        if ($TenantFilter -in $script:FailFetch) { throw 'no token' }
        $Plans = @{}
        foreach ($Plan in $script:Plans[$TenantFilter]) { $Plans[$Plan] = $true }
        [pscustomobject]$Plans
    }
}

Describe 'Update-CIPPDynamicTenantGroups' {
    BeforeEach {
        $script:Reads = [System.Collections.Generic.List[string]]::new()
        $script:Fetches = [System.Collections.Generic.List[string]]::new()
        $script:Added = [System.Collections.Generic.List[string]]::new()
        $script:Removed = [System.Collections.Generic.List[string]]::new()
        $script:FailFetch = @()
        $script:Plans = @{}
        $script:Tenants = @(
            [pscustomobject]@{ customerId = 'c1'; defaultDomainName = 'one.com'; displayName = 'One'; delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges' }
            [pscustomobject]@{ customerId = 'c2'; defaultDomainName = 'two.com'; displayName = 'Two'; delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges' }
            [pscustomobject]@{ customerId = 'c3'; defaultDomainName = 'three.com'; displayName = 'Three'; delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges' }
        )
        $LicenseRule = { param($Guid) "[{`"property`":`"availableLicense`",`"operator`":`"eq`",`"value`":{`"guid`":`"$Guid`"}}]" }
        $script:Rows = @{
            TenantGroups       = @(
                [pscustomobject]@{ RowKey = 'gA'; Name = 'A'; DynamicRules = (& $LicenseRule 'aaaaaaaa-0000-0000-0000-000000000000') }
                [pscustomobject]@{ RowKey = 'gB'; Name = 'B'; DynamicRules = (& $LicenseRule 'bbbbbbbb-0000-0000-0000-000000000000') }
            )
            TenantGroupMembers = @()
            cachetenantskus    = @(
                [pscustomobject]@{ RowKey = 'c1'; JSON = '[{"skuId":"aaaaaaaa-0000-0000-0000-000000000000","servicePlans":[]}]' }
                [pscustomobject]@{ RowKey = 'c3'; JSON = '' }
            )
        }
    }

    It 'loads the licence cache once and fetches each uncached tenant once across all groups' {
        $Result = Update-CIPPDynamicTenantGroups

        $Result.GroupsProcessed | Should -Be 2
        @($script:Reads | Where-Object { $_ -eq 'cachetenantskus' }).Count | Should -Be 1
        $script:Fetches | Should -Be @('two.com')
        $script:Added | Sort-Object | Should -Be @('gA-c1', 'gB-c2')
    }

    It 'skips the licence cache when no group has a licence rule' {
        $script:Rows.TenantGroups = @([pscustomobject]@{ RowKey = 'gC'; Name = 'C'; DynamicRules = '[{"property":"delegatedAccessStatus","operator":"eq","value":{"value":"granularDelegatedAdminPrivileges"}}]' })

        $null = Update-CIPPDynamicTenantGroups

        $script:Reads | Should -Not -Contain 'cachetenantskus'
        $script:Added | Sort-Object | Should -Be @('gC-c1', 'gC-c2', 'gC-c3')
    }

    It 'ne licence rule excludes a tenant holding the licence and includes one with no licences' {
        $script:Rows.cachetenantskus[0].JSON = '[{"skuId":"aaaaaaaa-0000-0000-0000-000000000000"},{"skuId":"cccccccc-0000-0000-0000-000000000000"}]'
        $script:Rows.TenantGroups = @([pscustomobject]@{ RowKey = 'gN'; Name = 'N'; DynamicRules = '[{"property":"availableLicense","operator":"ne","value":{"guid":"aaaaaaaa-0000-0000-0000-000000000000"}}]' })

        $null = Update-CIPPDynamicTenantGroups

        $script:Added | Sort-Object | Should -Be @('gN-c2', 'gN-c3')
    }

    It 'ne service plan rule excludes a tenant holding the plan and includes one with no plans' {
        $script:Plans = @{ 'one.com' = @('EXCHANGE_S_STANDARD', 'TEAMS1'); 'two.com' = @('TEAMS1'); 'three.com' = @() }
        $script:Rows.TenantGroups = @([pscustomobject]@{ RowKey = 'gP'; Name = 'P'; DynamicRules = '[{"property":"availableServicePlan","operator":"ne","value":{"value":"EXCHANGE_S_STANDARD"}}]' })

        $null = Update-CIPPDynamicTenantGroups

        $script:Added | Sort-Object | Should -Be @('gP-c2', 'gP-c3')
    }

    It 'tenantGroupMember <Operator> matches against every member of the referenced group' -ForEach @(
        @{ Operator = 'eq'; Expected = @('gM-c1', 'gM-c2') }
        @{ Operator = 'ne'; Expected = @('gM-c3') }
    ) {
        $Ref = '11111111-0000-0000-0000-000000000000'
        $script:Rows.TenantGroupMembers = @(
            [pscustomobject]@{ RowKey = "$Ref-c1"; GroupId = $Ref; customerId = 'c1' }
            [pscustomobject]@{ RowKey = "$Ref-c2"; GroupId = $Ref; customerId = 'c2' }
        )
        $script:Rows.TenantGroups = @([pscustomobject]@{ RowKey = 'gM'; Name = 'M'; DynamicRules = "[{`"property`":`"tenantGroupMember`",`"operator`":`"$Operator`",`"value`":{`"value`":`"$Ref`"}}]" })

        $null = Update-CIPPDynamicTenantGroups

        $script:Added | Sort-Object | Should -Be $Expected
    }

    It 'leaves membership alone when one of the rules is invalid' {
        $script:Rows.TenantGroupMembers = @([pscustomobject]@{ RowKey = 'gI-c1'; GroupId = 'gI'; customerId = 'c1' })
        $script:Rows.TenantGroups = @([pscustomobject]@{ RowKey = 'gI'; Name = 'I'; DynamicRules = '[{"property":"delegatedAccessStatus","operator":"eq","value":{"value":"granularDelegatedAdminPrivileges"}},{"property":"notAProperty","operator":"eq","value":{"value":"x"}}]' })

        $Result = Update-CIPPDynamicTenantGroups

        $Result.GroupsProcessed | Should -Be 0
        $script:Added | Should -BeNullOrEmpty
        $script:Removed | Should -BeNullOrEmpty
    }

    It 'keeps a member whose licences could not be read' {
        $script:FailFetch = @('two.com')
        $script:Rows.TenantGroupMembers = @([pscustomobject]@{ RowKey = 'gF-c2'; GroupId = 'gF'; customerId = 'c2' })
        $script:Rows.TenantGroups = @([pscustomobject]@{ RowKey = 'gF'; Name = 'F'; DynamicRules = '[{"property":"availableLicense","operator":"eq","value":{"guid":"aaaaaaaa-0000-0000-0000-000000000000"}}]' })

        $Result = Update-CIPPDynamicTenantGroups

        $Result.GroupsProcessed | Should -Be 1
        $script:Removed | Should -BeNullOrEmpty
        $script:Added | Should -Be @('gF-c1')
    }

    It 'does not add a tenant whose licences could not be read to a ne group' {
        $script:FailFetch = @('two.com')
        $script:Rows.TenantGroups = @([pscustomobject]@{ RowKey = 'gN'; Name = 'N'; DynamicRules = '[{"property":"availableLicense","operator":"ne","value":{"guid":"aaaaaaaa-0000-0000-0000-000000000000"}}]' })

        $null = Update-CIPPDynamicTenantGroups

        $script:Added | Should -Be @('gN-c3')
    }
}

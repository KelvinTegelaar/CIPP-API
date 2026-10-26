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
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-Tenants { param([switch]$IncludeErrors) $script:Tenants }
    function New-GraphGetRequest { param($uri, $TenantId) $script:Fetches.Add($TenantId); @([pscustomobject]@{ skuId = 'bbbbbbbb-0000-0000-0000-000000000000' }) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-TenantGroups { param([switch]$SkipCache) }
    function Clear-CippAccessScopeCache {}
}

Describe 'Update-CIPPDynamicTenantGroups' {
    BeforeEach {
        $script:Reads = [System.Collections.Generic.List[string]]::new()
        $script:Fetches = [System.Collections.Generic.List[string]]::new()
        $script:Added = [System.Collections.Generic.List[string]]::new()
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
}

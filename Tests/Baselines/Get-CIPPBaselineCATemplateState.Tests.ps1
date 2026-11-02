# Pester tests for the ConditionalAccessTemplate prepare hook: the stored template is normalized into
# the Expected side and the cached live policy into Current, ids translated to display names.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTextReplacement.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks/Get-CIPPBaselineCATemplateState.ps1')

    $script:UserId = '10000000-0000-0000-0000-000000000001'
    $script:SiteAId = '30000000-0000-0000-0000-00000000000a'

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'cust-1'; defaultDomainName = 'customer.example.com'; displayName = 'Customer' } }
    function Get-CIPPSchemaExtensions { }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity {
        param($TableName, $Filter)
        if ($TableName -eq 'templates') { return [pscustomobject]@{ RowKey = 'tpl-1'; GUID = 'tpl-1'; JSON = $script:TemplateJSON } }
        if ($Filter -match "PartitionKey eq 'AllTenants'") { return $script:VariableRows }
        @()
    }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-CIPPDbRequest {
        param($TenantFilter, $Type, $Fields)
        switch ($Type) {
            'NamedLocations' { [pscustomobject]@{ id = $script:SiteAId; displayName = 'Site A' } }
            'Users' { [pscustomobject]@{ id = $script:UserId; displayName = 'Break Glass' } }
            'Groups' { $script:CachedGroups }
            'ConditionalAccessPolicies' { $script:LivePolicy | ConvertTo-Json -Depth 20 | ConvertFrom-Json }
        }
    }

    $script:CachedGroups = @()
    $script:GraphLookups = [System.Collections.Generic.List[object]]::new()
    $script:LiveDirectory = @()
    function New-GraphPOSTRequest {
        param($uri, $tenantid, $body, $AsApp)
        $script:GraphLookups.Add(($body | ConvertFrom-Json))
        [pscustomobject]@{ value = @($script:LiveDirectory | Where-Object { $_.id -in ($body | ConvertFrom-Json).ids }) }
    }

    $script:VariableRows = @(
        [pscustomobject]@{ RowKey = 'breakglass'; Value = 'Break Glass' }
        [pscustomobject]@{ RowKey = 'sites'; Value = '["Site A","Site B"]'; VariableType = 'list' }
    )
    $script:LivePolicy = [pscustomobject]@{
        id          = 'live-id'
        displayName = 'Variable test policy'
        state       = 'disabled'
        conditions  = [pscustomobject]@{
            users     = [pscustomobject]@{ includeUsers = @('All'); excludeUsers = @($script:UserId) }
            locations = [pscustomobject]@{ includeLocations = @('All'); excludeLocations = @($script:SiteAId) }
        }
    }

    function Get-State {
        param([string]$ExcludeUsers, [string]$ExcludeLocations)
        $script:TemplateJSON = '{{"displayName":"Variable test policy","state":"disabled","conditions":{{"users":{{"includeUsers":["All"],"excludeUsers":[{0}]}},"locations":{{"includeLocations":["All"],"excludeLocations":[{1}]}}}}}}' -f $ExcludeUsers, $ExcludeLocations
        Get-CIPPBaselineCATemplateState -Item @{ Variables = @{ caTemplate = 'tpl-1'; state = 'donotchange' } } -TenantFilter 'customer.example.com'
    }
}

Describe 'Get-CIPPBaselineCATemplateState' {
    It 'translates ids on both sides to display names' {
        $State = Get-State ('"{0}"' -f $script:UserId) ('"{0}"' -f $script:SiteAId)
        @($State.Expected.conditions.users.excludeUsers) | Should -Be @('Break Glass')
        @($State.Current.conditions.users.excludeUsers) | Should -Be @('Break Glass')
        @($State.Expected.conditions.locations.excludeLocations) | Should -Be @('Site A')
        @($State.Current.conditions.locations.excludeLocations) | Should -Be @('Site A')
    }

    It 'keeps a name already in the template as the name' {
        $State = Get-State '"Break Glass"' '"Site A"'
        @($State.Expected.conditions.users.excludeUsers) | Should -Be @('Break Glass')
        @($State.Expected.conditions.locations.excludeLocations) | Should -Be @('Site A')
    }

    It 'resolves custom variables on the expected side' {
        $State = Get-State '"%breakglass%"' '"%sites%"'
        @($State.Expected.conditions.users.excludeUsers) | Should -Be @('Break Glass')
        @($State.Expected.conditions.locations.excludeLocations) | Should -Be @('Site A', 'Site B')
    }

    Context 'excludeGroups the Groups cache does not hold yet' {
        BeforeAll {
            $script:GroupA = '20000000-0000-0000-0000-00000000000a'
            $script:GroupB = '20000000-0000-0000-0000-00000000000b'
            $script:GroupC = '20000000-0000-0000-0000-00000000000c'
            $script:Vacation = '20000000-0000-0000-0000-0000000000ff'
            $script:SavedPolicy = $script:LivePolicy
        }
        AfterAll {
            $script:LivePolicy = $script:SavedPolicy
            $script:CachedGroups = @()
            $script:LiveDirectory = @()
        }

        It 'resolves groups created after the last Groups collection so a correct policy does not drift' {
            # Only GroupA was cached; B and C were created by the deploy, the vacation group by vacation mode.
            $script:CachedGroups = @([pscustomobject]@{ id = $script:GroupA; displayName = 'Exclude A' })
            $script:LiveDirectory = @(
                [pscustomobject]@{ id = $script:GroupB; displayName = 'Exclude B' }
                [pscustomobject]@{ id = $script:GroupC; displayName = 'Exclude C' }
                [pscustomobject]@{ id = $script:Vacation; displayName = 'Vacation Exclusion - Variable test policy' }
            )
            $script:GraphLookups.Clear()
            $script:LivePolicy = [pscustomobject]@{
                id          = 'live-id'
                displayName = 'Variable test policy'
                state       = 'disabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{ includeUsers = @('All'); excludeGroups = @($script:GroupA, $script:GroupB, $script:GroupC, $script:Vacation) }
                }
            }
            $script:TemplateJSON = '{"displayName":"Variable test policy","state":"disabled","conditions":{"users":{"includeUsers":["All"],"excludeGroups":["Exclude A","Exclude B","Exclude C"]}}}'
            $State = Get-CIPPBaselineCATemplateState -Item @{ Variables = @{ caTemplate = 'tpl-1'; state = 'donotchange' } } -TenantFilter 'customer.example.com'

            @($State.Current.conditions.users.excludeGroups | Sort-Object) | Should -Be @('Exclude A', 'Exclude B', 'Exclude C')
            @($State.Expected.conditions.users.excludeGroups | Sort-Object) | Should -Be @('Exclude A', 'Exclude B', 'Exclude C')
            $script:GraphLookups.Count | Should -Be 1
            @($script:GraphLookups[0].ids | Sort-Object) | Should -Be @($script:GroupB, $script:GroupC, $script:Vacation)
        }

        It 'makes no live lookup when the caches resolve every id' {
            $script:CachedGroups = @([pscustomobject]@{ id = $script:GroupA; displayName = 'Exclude A' })
            $script:GraphLookups.Clear()
            $script:LivePolicy = [pscustomobject]@{
                displayName = 'Variable test policy'
                state       = 'disabled'
                conditions  = [pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @('All'); excludeGroups = @($script:GroupA) } }
            }
            $script:TemplateJSON = '{"displayName":"Variable test policy","state":"disabled","conditions":{"users":{"includeUsers":["All"],"excludeGroups":["Exclude A"]}}}'
            $State = Get-CIPPBaselineCATemplateState -Item @{ Variables = @{ caTemplate = 'tpl-1'; state = 'donotchange' } } -TenantFilter 'customer.example.com'

            @($State.Current.conditions.users.excludeGroups) | Should -Be @('Exclude A')
            $script:GraphLookups.Count | Should -Be 0
        }
    }
}

# Pester tests for the ConditionalAccessTemplate prepare hook: the stored template is normalized into
# the Expected side and the cached live policy into Current, ids translated to display names.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTextReplacement.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks/Get-CIPPBaselineCATemplateState.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPNamedLocationRange.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')

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
            'NamedLocations' { $script:TenantLocations ?? [pscustomobject]@{ id = $script:SiteAId; displayName = 'Site A' } }
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

        It 'ignores Vacation Exclusion groups in a template captured from a policy that had them' {
            $script:CachedGroups = @(
                [pscustomobject]@{ id = $script:GroupA; displayName = 'Exclude A' }
                [pscustomobject]@{ id = $script:Vacation; displayName = 'Vacation Exclusion - Variable test policy' }
            )
            $script:LivePolicy = [pscustomobject]@{
                displayName = 'Variable test policy'
                state       = 'disabled'
                conditions  = [pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @('All'); excludeGroups = @($script:GroupA) } }
            }
            $script:TemplateJSON = '{"displayName":"Variable test policy","state":"disabled","conditions":{"users":{"includeUsers":["All"],"excludeGroups":["Exclude A","Vacation Exclusion - Variable test policy"]}}}'
            $State = Get-CIPPBaselineCATemplateState -Item @{ Variables = @{ caTemplate = 'tpl-1'; state = 'donotchange' } } -TenantFilter 'customer.example.com'

            @($State.Expected.conditions.users.excludeGroups) | Should -Be @('Exclude A')
            @($State.Current.conditions.users.excludeGroups) | Should -Be @('Exclude A')
        }
    }

    Context 'named location contents' {
        BeforeAll {
            $script:SavedPolicy = $script:LivePolicy
            $script:SavedVariables = $script:VariableRows
            $script:TemplateJSON = @'
{"displayName":"Location test policy","state":"disabled",
 "conditions":{"users":{"includeUsers":["All"]},"locations":{"includeLocations":["All"],"excludeLocations":["Office IPs","Allowed Countries","%clientallowlocations%"]}},
 "LocationInfo":[
  {"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Office IPs","isTrusted":false,"ipRanges":[{"@odata.type":"#microsoft.graph.iPv4CidrRange","cidrAddress":"%officeips%"}]},
  {"@odata.type":"#microsoft.graph.countryNamedLocation","displayName":"Allowed Countries","countriesAndRegions":["%allowedcountries%"],"includeUnknownCountriesAndRegions":false},
  {"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Unused","isTrusted":true,"ipRanges":[{"@odata.type":"#microsoft.graph.iPv4CidrRange","cidrAddress":"192.0.2.1/32"}]}
 ]}
'@
            function New-IpLocation($Id, $Name, [string[]]$Cidrs) {
                [pscustomobject]@{ '@odata.type' = '#microsoft.graph.ipNamedLocation'; id = $Id; displayName = $Name; isTrusted = $false; ipRanges = @($Cidrs | ForEach-Object { [pscustomobject]@{ '@odata.type' = '#microsoft.graph.iPv4CidrRange'; cidrAddress = $_ } }) }
            }
            $script:Countries = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.countryNamedLocation'; id = 'loc-countries'; displayName = 'Allowed Countries'; countriesAndRegions = @('BE', 'NL'); includeUnknownCountriesAndRegions = $false; countryLookupMethod = 'clientIpAddress' }
            function Set-Variables($OfficeIps = '["203.0.113.0/24","198.51.100.10/32"]', $ClientAllow = '[]') {
                $script:VariableRows = @(
                    [pscustomobject]@{ RowKey = 'officeips'; Value = $OfficeIps; VariableType = 'list' }
                    [pscustomobject]@{ RowKey = 'allowedcountries'; Value = '["NL","BE"]'; VariableType = 'list' }
                    [pscustomobject]@{ RowKey = 'clientallowlocations'; Value = $ClientAllow; VariableType = 'list' }
                )
            }
            function Get-LocationDrift([string[]]$BoundIds) {
                $script:LivePolicy = [pscustomobject]@{
                    displayName = 'Location test policy'
                    state       = 'disabled'
                    conditions  = [pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @('All') }; locations = [pscustomobject]@{ includeLocations = @('All'); excludeLocations = $BoundIds } }
                }
                $State = Get-CIPPBaselineCATemplateState -Item @{ Variables = @{ caTemplate = 'tpl-1'; state = 'donotchange' } } -TenantFilter 'customer.example.com'
                [pscustomobject]@{
                    State       = $State
                    Differences = @(Compare-CIPPIntuneObject -ReferenceObject $State.Expected -DifferenceObject $State.Current | Where-Object { $_ })
                }
            }
        }
        BeforeEach {
            Set-Variables
            $script:TenantLocations = @((New-IpLocation 'loc-office' 'Office IPs' '198.51.100.10/32', '203.0.113.0/24'), $script:Countries)
        }
        AfterAll {
            $script:LivePolicy = $script:SavedPolicy
            $script:VariableRows = $script:SavedVariables
            $script:TenantLocations = $null
        }

        It 'grades list-variable ranges and countries as compliant regardless of order' {
            $Result = Get-LocationDrift 'loc-office', 'loc-countries'
            $Result.State.Expected.namedLocations.'Office IPs'.ipRanges | Should -Be '198.51.100.10/32, 203.0.113.0/24'
            $Result.State.Expected.namedLocations.'Allowed Countries'.countriesAndRegions | Should -Be 'BE, NL'
            $Result.Differences | Should -BeNullOrEmpty
        }

        It 'drifts when the variable gains a range the tenant location lacks' {
            Set-Variables -OfficeIps '["203.0.113.0/24","198.51.100.10/32","192.0.2.0/24"]'
            $Result = Get-LocationDrift 'loc-office', 'loc-countries'
            @($Result.Differences.Property) | Should -Be @('namedLocations.Office IPs.ipRanges')
        }

        It 'grades the copy the policy is bound to when the tenant has duplicates' {
            $script:TenantLocations = @((New-IpLocation 'loc-old' 'Office IPs' '10.0.0.0/8'), (New-IpLocation 'loc-office' 'Office IPs' '198.51.100.10/32', '203.0.113.0/24'), $script:Countries)
            (Get-LocationDrift 'loc-office', 'loc-countries').Differences | Should -BeNullOrEmpty
            (Get-LocationDrift 'loc-old', 'loc-countries').Differences | Should -Not -BeNullOrEmpty
        }

        It 'drifts when a defined location is missing from the tenant' {
            $script:TenantLocations = @($script:Countries)
            $Result = Get-LocationDrift 'loc-countries'
            $Result.State.Current.namedLocations.'Office IPs' | Should -BeNullOrEmpty
            $Result.Differences | Should -Not -BeNullOrEmpty
        }

        It 'never grades a tenant-managed location named through a list variable, nor an unreferenced one' {
            Set-Variables -ClientAllow '["Client Allow"]'
            $script:TenantLocations = @((New-IpLocation 'loc-office' 'Office IPs' '198.51.100.10/32', '203.0.113.0/24'), $script:Countries, (New-IpLocation 'loc-client' 'Client Allow' '100.64.0.0/10'))
            $Result = Get-LocationDrift 'loc-office', 'loc-countries', 'loc-client'
            @($Result.State.Expected.namedLocations.PSObject.Properties.Name) | Should -Be @('Office IPs', 'Allowed Countries')
            $Result.Differences | Should -BeNullOrEmpty
        }

        It 'drops an empty list variable from the references' {
            $Result = Get-LocationDrift 'loc-office', 'loc-countries'
            @($Result.State.Expected.conditions.locations.excludeLocations) | Should -Be @('Office IPs', 'Allowed Countries')
        }
    }
}

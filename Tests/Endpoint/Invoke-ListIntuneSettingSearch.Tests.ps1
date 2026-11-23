BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, $Partition) }
    function Get-CIPPIntuneDefinitionIndex {}
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) $Exception }

    foreach ($Name in 'Get-CIPPIntunePolicyListDefinitions', 'ConvertTo-CIPPIntunePolicyListItem', 'ConvertTo-CIPPIntunePolicySetting', 'ConvertTo-CIPPODataFilterValue', 'Get-CippErrorStatusCode') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Name.ps1")
    }
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListIntuneSettingSearch.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Catalog = '11111111-1111-4111-8111-111111111111'
    $script:Catalog2 = '66666666-6666-4666-8666-666666666666'
    $script:Compliance = '22222222-2222-4222-8222-222222222222'
    $script:EmptyCatalog = '44444444-4444-4444-8444-444444444444'
    $script:Feature = '55555555-5555-4555-8555-555555555555'
    $script:RealtimeId = 'device_vendor_msft_defender_allowrealtimemonitoring'

    function Invoke-Search([string]$Search, [string]$TenantFilter = $script:Tenant) {
        $Query = [PSCustomObject]@{ tenantFilter = $TenantFilter; search = $Search }
        Invoke-ListIntuneSettingSearch -Request ([PSCustomObject]@{ Query = $Query }) -TriggerMetadata $null
    }

    function New-DbItem([string]$Type, $Data) {
        [PSCustomObject]@{ PartitionKey = $script:Tenant; RowKey = "$Type-$($Data.id)"; Data = $Data | ConvertTo-Json -Depth 20 -Compress }
    }

    function Add-DbItem([string]$Type, $Data) {
        $script:RowsByType[$Type] = @($script:RowsByType[$Type]) + @(New-DbItem $Type $Data)
    }

    function New-OmaPolicy([string]$Id, [string]$Name, [string[]]$SettingNames) {
        @{
            '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
            id            = $Id
            displayName   = $Name
            omaSettings   = @(foreach ($SettingName in $SettingNames) { @{ '@odata.type' = '#microsoft.graph.omaSettingInteger'; displayName = $SettingName; omaUri = "./Vendor/$SettingName"; value = 1 } })
        }
    }

    function New-CatalogPolicy([string]$Id, [string]$Name, [string[]]$Options) {
        @{
            id       = $Id
            name     = $Name
            settings = @(foreach ($Option in $Options) {
                    @{
                        id              = '0'
                        settingInstance = @{
                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                            settingDefinitionId = $script:RealtimeId
                            choiceSettingValue  = @{ value = "$($script:RealtimeId)_$Option"; children = @() }
                        }
                    }
                })
        }
    }

    function New-TableRow([string]$RowKey) {
        [PSCustomObject]@{ PartitionKey = $script:Tenant; RowKey = $RowKey }
    }

    function Select-TableRow([string]$Filter) {
        if ($Filter -notmatch "^PartitionKey eq '(.+)' and RowKey ge '(.+)' and RowKey lt '(.+)'$") { throw "Unexpected filter $Filter" }
        $Partition, $From, $To = $Matches[1], $Matches[2], $Matches[3]
        $script:Table | Where-Object {
            $_.PartitionKey -eq $Partition -and [string]::CompareOrdinal($_.RowKey, $From) -ge 0 -and [string]::CompareOrdinal($_.RowKey, $To) -lt 0
        }
    }
}

Describe 'Invoke-ListIntuneSettingSearch' {
    BeforeEach {
        $script:RowsByType = @{
            IntuneConfigurationPolicies     = @(
                New-DbItem 'IntuneConfigurationPolicies' (New-CatalogPolicy $script:Catalog 'Defender A' '1')
                [PSCustomObject]@{ PartitionKey = $script:Tenant; RowKey = 'IntuneConfigurationPolicies-Count'; Data = '{"Count":1}' }
            )
            IntuneDeviceConfigurations      = @(
                New-DbItem 'IntuneDeviceConfigurations' @{
                    '@odata.type'                     = '#microsoft.graph.windows10GeneralConfiguration'
                    'assignments@odata.context'       = "https://graph.microsoft.com/beta/`$metadata#deviceManagement/deviceConfigurations('x')/microsoft.graph.windows10GeneralConfiguration/assignments"
                    id                                = 'gen-a'
                    displayName                       = 'Windows A'
                    passwordMinimumLength             = 12
                    defenderRequireRealTimeMonitoring = $true
                    cortanaBlocked                    = $false
                    printerBlockAddition              = $false
                }
                New-DbItem 'IntuneDeviceConfigurations' @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    id            = 'oma-a'
                    displayName   = 'Custom A'
                    omaSettings   = @(@{ displayName = 'Realtime OMA'; omaUri = './Vendor/MSFT/Defender/RealTime'; value = 1 })
                }
            )
            IntuneGroupPolicyConfigurations = @(New-DbItem 'IntuneGroupPolicyConfigurations' @{ id = 'adm-a'; displayName = 'Realtime admx'; realtimeProperty = 'x' })
            IntuneIntents                   = @(New-DbItem 'IntuneIntents' @{ id = 'int-a'; displayName = 'Realtime intent'; realtimeProperty = 'x' })
        }
        $script:Table = @()

        $Options = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Options["$($script:RealtimeId)_0"] = 'Not allowed'
        $Options["$($script:RealtimeId)_1"] = 'Allowed'
        $script:Index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $script:Index[$script:RealtimeId] = @{ displayName = 'Allow Realtime Monitoring'; options = $Options }

        Mock Write-LogMessage {}
        Mock Get-CIPPIntuneDefinitionIndex { $script:Index }
        Mock Get-Tenants { [PSCustomObject]@{ defaultDomainName = $script:Tenant } }
        Mock Get-CIPPDbItem { @($script:RowsByType[$Type] | Where-Object { $_.PartitionKey -eq $Partition }) }
        Mock Get-CIPPAzDataTableEntity { Select-TableRow $Filter }
    }

    Context 'request validation' {
        It 'rejects <Name> before reading the cache' -ForEach @(
            @{ Name = 'AllTenants'; TenantFilter = 'AllTenants'; Search = 'password' }
            @{ Name = 'AllTenants in any case'; TenantFilter = 'alltenants'; Search = 'password' }
            @{ Name = 'AllTenants with a short search'; TenantFilter = 'AllTenants'; Search = 'a' }
            @{ Name = 'a missing tenant'; TenantFilter = ''; Search = 'password' }
        ) {
            $Response = Invoke-Search $Search $TenantFilter

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -BeLike '*single tenant*'
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
        }

        It 'rejects a search of <Name>' -ForEach @(
            @{ Name = 'one character'; Search = ' a ' }
            @{ Name = 'two characters'; Search = ' ab ' }
        ) {
            $Response = Invoke-Search $Search

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -BeLike '*at least 3 characters*'
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
        }

        It 'is not marked for tenant groups, so the router refuses a tenantGroup request' {
            (Get-Help Invoke-ListIntuneSettingSearch).Functionality | Should -Be 'Entrypoint'
        }

        It 'returns 404 when the tenant is not known' {
            Mock Get-Tenants {}

            $Response = Invoke-Search 'realtime'

            $Response.StatusCode | Should -Be 404
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
        }

        It 'returns 500 with the error when the cache cannot be read' {
            Mock Get-CIPPDbItem { throw 'cache unavailable' }

            $Response = Invoke-Search 'realtime'

            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -Be 'cache unavailable'
        }
    }

    Context 'searching' {
        It 'matches the trimmed search case-insensitively across setting kinds' {
            $Response = Invoke-Search '  REALTIME '
            $Result = @($Response.Body.Results)

            $Response.StatusCode | Should -Be 200
            $Response.Body.Metadata.Truncated | Should -BeFalse
            $Result.SettingId | Should -Be @(
                $script:RealtimeId
                'windows10GeneralConfiguration/defenderRequireRealTimeMonitoring'
                './Vendor/MSFT/Defender/RealTime'
            )
            $Catalog = $Result[0]
            $Catalog.SettingName | Should -Be 'Allow Realtime Monitoring'
            $Catalog.Category | Should -Be 'Device Configuration'
            $Catalog.PolicyCount | Should -Be 1
            $Catalog.PolicyTypes | Should -Be 'Device Configuration'
            $Catalog.Policies[0].Tenant | Should -Be $script:Tenant
            $Catalog.Policies[0].PolicyId | Should -Be $script:Catalog
            $Catalog.Policies[0].PolicyName | Should -Be 'Defender A'
            $Catalog.Policies[0].PolicyTypeName | Should -Be 'Device Configuration'
            $Catalog.Policies[0].URLName | Should -Be 'ConfigurationPolicies'
            $Catalog.Policies[0].Value | Should -Be 'Allowed'

            $Result[1].SettingName | Should -Be 'Defender require real time monitoring'
            $Result[1].Category | Should -Be 'Windows Configuration'
            $Result[1].Policies[0].URLName | Should -Be 'DeviceConfigurations'
            $Result[1].Policies[0].Value | Should -Be 'true'

            $Result[2].SettingName | Should -Be 'Realtime OMA'
            $Result[2].Category | Should -Be 'windows10CustomConfiguration'
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $Partition -ne $script:Tenant }
        }

        It 'uses the policy type label from the assignment context as the category' {
            $script:RowsByType['IntuneDeviceConfigurations'] = @(
                New-DbItem 'IntuneDeviceConfigurations' ((New-OmaPolicy 'oma-a' 'Custom A' @('Realtime OMA')) + @{
                        'assignments@odata.context' = "https://graph.microsoft.com/beta/`$metadata#deviceManagement/deviceConfigurations('x')/microsoft.graph.windows10CustomConfiguration/assignments"
                    })
            )

            $Result = @((Invoke-Search 'Realtime OMA').Body.Results)

            $Result.Category | Should -Be 'Custom'
            $Result.Policies.PolicyTypeName | Should -Be 'Custom'
        }

        It 'matches the setting id' {
            $Result = @((Invoke-Search 'passwordMinimum').Body.Results)

            $Result.SettingId | Should -Be 'windows10GeneralConfiguration/passwordMinimumLength'
            $Result.Policies.Value | Should -Be '12'
        }

        It 'does not match booleans the policy leaves unset' {
            @((Invoke-Search 'cortana').Body.Results) | Should -HaveCount 0
            @((Invoke-Search 'printer').Body.Results) | Should -HaveCount 0
        }

        It 'skips families whose settings are not cached' {
            @((Invoke-Search 'realtimeProperty').Body.Results) | Should -HaveCount 0
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $Type -in @('IntuneGroupPolicyConfigurations', 'IntuneIntents') }
        }

        It 'returns no rows when nothing matches' {
            $Response = Invoke-Search 'nothing-matches-this'

            $Response.StatusCode | Should -Be 200
            ($Response.Body | ConvertTo-Json -Depth 5 -Compress) | Should -BeLike '*"Results":`[`]*'
        }

        It 'skips cached rows that cannot be parsed' {
            $script:RowsByType['IntuneConfigurationPolicies'] += [PSCustomObject]@{ PartitionKey = $script:Tenant; RowKey = 'bad'; Data = '{not json' }

            @((Invoke-Search 'Allow Realtime').Body.Results) | Should -HaveCount 1
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' }
        }
    }

    Context 'grouping policies' {
        It 'groups one setting across policies sorted by policy name' {
            Add-DbItem 'IntuneConfigurationPolicies' (New-CatalogPolicy $script:Catalog2 'Another Defender' '0')

            $Result = @((Invoke-Search 'allow realtime').Body.Results)

            $Result | Should -HaveCount 1
            $Result[0].PolicyCount | Should -Be 2
            $Result[0].Policies.PolicyName | Should -Be @('Another Defender', 'Defender A')
            $Result[0].Policies.Value | Should -Be @('Not allowed', 'Allowed')
        }

        It 'lists the distinct policy types of a setting sorted' {
            $EndpointProtection = "https://graph.microsoft.com/beta/`$metadata#deviceManagement/deviceConfigurations('x')/microsoft.graph.windows10EndpointProtectionConfiguration/assignments"
            $script:RowsByType['IntuneConfigurationPolicies'] = @(
                New-DbItem 'IntuneConfigurationPolicies' ((New-CatalogPolicy 'cat-a' 'Defender A' '1') + @{ 'assignments@odata.context' = $EndpointProtection })
                New-DbItem 'IntuneConfigurationPolicies' (New-CatalogPolicy 'cat-b' 'Defender B' '0')
                New-DbItem 'IntuneConfigurationPolicies' ((New-CatalogPolicy 'cat-c' 'Defender C' '1') + @{ 'assignments@odata.context' = $EndpointProtection })
            )

            $Result = @((Invoke-Search 'allow realtime').Body.Results)

            $Result[0].PolicyCount | Should -Be 3
            $Result[0].PolicyTypes | Should -Be 'Device Configuration, Endpoint Protection'
        }

        It 'lists a policy once with each value once, in the order first seen' {
            $script:RowsByType['IntuneConfigurationPolicies'] = @(New-DbItem 'IntuneConfigurationPolicies' (New-CatalogPolicy 'cat-multi' 'Multi' @('1', '0', '1')))

            $Result = @((Invoke-Search 'Allow Realtime').Body.Results)

            $Result.PolicyCount | Should -Be 1
            $Result.Policies.Value | Should -Be 'Allowed, Not allowed'
        }
    }

    Context 'the result cap' {
        BeforeEach {
            $script:RowsByType['IntuneConfigurationPolicies'] = @()
            $script:CappedNames = @(1..500 | ForEach-Object { 'Capped {0:d3}' -f $_ })
        }

        It 'returns exactly 500 settings without marking them truncated' {
            $script:RowsByType['IntuneDeviceConfigurations'] = @(New-DbItem 'IntuneDeviceConfigurations' (New-OmaPolicy $script:Compliance 'First' $script:CappedNames))

            $Response = Invoke-Search 'Capped'

            @($Response.Body.Results) | Should -HaveCount 500
            $Response.Body.Metadata.Truncated | Should -BeFalse
        }

        It 'keeps the first 500 settings found, sorted, and still adds later policies to them' {
            $script:RowsByType['IntuneDeviceConfigurations'] = @(
                New-DbItem 'IntuneDeviceConfigurations' (New-OmaPolicy 'oma-1' 'First' ($script:CappedNames + 'Capped 999'))
                New-DbItem 'IntuneDeviceConfigurations' (New-OmaPolicy 'oma-2' 'Second' @('Capped 000', 'Capped 002'))
            )

            $Response = Invoke-Search 'Capped'
            $Result = @($Response.Body.Results)

            $Response.StatusCode | Should -Be 200
            $Response.Body.Metadata.Truncated | Should -BeTrue
            $Result | Should -HaveCount 500
            $Result[0].SettingName | Should -Be 'Capped 001'
            $Result[-1].SettingName | Should -Be 'Capped 500'
            $Result[1].Policies.PolicyId | Should -Be @('oma-1', 'oma-2')
        }

        It 'counts devices for the returned settings only' {
            $script:RowsByType['IntuneDeviceConfigurations'] = @(
                New-DbItem 'IntuneDeviceConfigurations' (New-OmaPolicy $script:Compliance 'First' $script:CappedNames)
                New-DbItem 'IntuneDeviceConfigurations' (New-OmaPolicy $script:Feature 'Second' @('Capped 999'))
            )

            $null = Invoke-Search 'Capped'

            Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
            Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Filter -like "*$script:Feature*" }
        }
    }

    Context 'device counts' {
        BeforeEach {
            $script:RowsByType['IntuneConfigurationPolicies'] = @(
                New-DbItem 'IntuneConfigurationPolicies' (New-CatalogPolicy $script:Catalog 'Defender A' '1')
                New-DbItem 'IntuneConfigurationPolicies' (New-CatalogPolicy $script:Catalog2 'Defender B' '1')
            )
            $script:RowsByType['IntuneDeviceCompliancePolicies'] = @(
                New-DbItem 'IntuneDeviceCompliancePolicies' @{ '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'; id = $script:Compliance; displayName = 'Compliance'; realtimeProtectionEnabled = $true }
            )
            $script:Table = @(
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog-dev-1|PC1|user-1"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog-dev-1|PC1|00000000-0000-0000-0000-000000000000"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog-dev-2|PC2|user-2"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog-Count"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog2-dev-2|PC2|user-2"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog2-dev-3|PC3|user-3"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog2-Count"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:EmptyCatalog-Count"
                New-TableRow "IntuneDeviceCompliancePolicies_$script:Compliance-x_$($script:Compliance)_dev-2"
                New-TableRow "IntuneDeviceCompliancePolicies_$script:Compliance-x_$($script:Compliance)_dev-3"
                New-TableRow "IntuneDeviceCompliancePolicies-$script:Compliance"
            )
        }

        It 'counts distinct devices per policy and across the policies of a setting' {
            $Result = @((Invoke-Search 'realtime').Body.Results)

            $Catalog = $Result | Where-Object SettingId -EQ $script:RealtimeId
            $Catalog.Policies.DeviceCount | Should -Be @(2, 2)
            $Catalog.DeviceCount | Should -Be 3
            ($Result | Where-Object SettingId -EQ 'windows10CompliancePolicy/realtimeProtectionEnabled').DeviceCount | Should -Be 2
        }

        It 'reads only the policies in the results, one row-key range per policy' {
            $null = Invoke-Search 'realtime'

            Should -Invoke Get-CIPPAzDataTableEntity -Times 3 -Exactly
            Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Filter -eq "PartitionKey eq '$script:Tenant' and RowKey ge 'IntuneConfigurationPolicyDevices_$script:Catalog-' and RowKey lt 'IntuneConfigurationPolicyDevices_$script:Catalog.'" -and
                (@($Property) -join ',') -eq 'PartitionKey,RowKey'
            }
        }

        It 'counts a device keyed by name in one row and by id in another once' {
            $script:Table += @(
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog-|pc1|user-9"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog2-|PC1|user-1"
                New-TableRow "IntuneConfigurationPolicyDevices_$script:Catalog2-|PC|9|user-1"
            )

            $Catalog = @((Invoke-Search 'allow realtime').Body.Results)[0]

            $Catalog.Policies.DeviceCount | Should -Be @(2, 4)
            $Catalog.DeviceCount | Should -Be 4
        }

        It 'is null when no policy has cached device data' {
            $script:Table = @()

            $Catalog = @((Invoke-Search 'allow realtime').Body.Results)[0]

            $Catalog.DeviceCount | Should -BeNullOrEmpty
            $Catalog.PSObject.Properties['DeviceCount'] | Should -Not -BeNullOrEmpty
            @($Catalog.Policies | Where-Object { $null -ne $_.DeviceCount }) | Should -HaveCount 0
        }

        It 'is 0 when a policy has a cached report without devices' {
            $script:RowsByType['IntuneConfigurationPolicies'] = @(New-DbItem 'IntuneConfigurationPolicies' (New-CatalogPolicy $script:EmptyCatalog 'Empty' '1'))

            $Catalog = @((Invoke-Search 'allow realtime').Body.Results)[0]

            $Catalog.DeviceCount | Should -Be 0
            $Catalog.DeviceCount | Should -BeOfType [int]
            $Catalog.Policies[0].DeviceCount | Should -Be 0
        }

        It 'reads a whole family once when many of its policies are in the results' {
            foreach ($Number in 1..5) {
                Add-DbItem 'IntuneConfigurationPolicies' (New-CatalogPolicy ('{0:d8}-0000-4000-8000-000000000000' -f $Number) "Other $Number" '1')
            }

            $Catalog = @((Invoke-Search 'allow realtime').Body.Results)[0]

            Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Filter -eq "PartitionKey eq '$script:Tenant' and RowKey ge 'IntuneConfigurationPolicyDevices_' and RowKey lt 'IntuneConfigurationPolicyDevices``'"
            }
            $Catalog.DeviceCount | Should -Be 3
            @($Catalog.Policies | Where-Object { $null -ne $_.DeviceCount }) | Should -HaveCount 2
        }

        It 'reads the reporting partition of a tenant searched by another domain' {
            Mock Get-Tenants { [PSCustomObject]@{ defaultDomainName = $script:Tenant } } -ParameterFilter { $TenantFilter -eq 'contoso.com' }

            $Catalog = @((Invoke-Search 'allow realtime' 'contoso.com').Body.Results)[0]

            $Catalog.DeviceCount | Should -Be 3
            $Catalog.Policies[0].Tenant | Should -Be 'contoso.com'
        }

        It 'returns the settings with a warning log when devices cannot be counted' {
            Mock Get-CIPPAzDataTableEntity { throw 'table unavailable' }

            $Response = Invoke-Search 'allow realtime'

            $Response.StatusCode | Should -Be 200
            @($Response.Body.Results) | Should -HaveCount 1
            $Response.Body.Results[0].DeviceCount | Should -BeNullOrEmpty
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*table unavailable*' }
        }
    }
}

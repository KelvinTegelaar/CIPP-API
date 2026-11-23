BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, $Partition) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    foreach ($Name in 'Get-CIPPIntuneReportRows', 'Get-CIPPIntuneDeploymentStatus', 'Get-CIPPIntunePolicyReportTypeFilter', 'Get-CIPPIntunePolicyListDefinitions', 'ConvertTo-CIPPODataFilterValue', 'Get-CippBulkStatusCode') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Name.ps1")
    }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListIntuneSettingDevices.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:Partition = 'contoso.onmicrosoft.com'
    $script:ConfigId = '3697484d-68b1-4888-b143-5b281cecc156'
    $script:ComplianceId = 'a1b2c3d4-0000-4000-8000-000000000001'
    $script:CatalogId = 'b1b2c3d4-0000-4000-8000-000000000002'

    function Invoke-Devices {
        param([string]$Policies, [string]$TenantFilter = 'contoso.com')
        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListIntuneSettingDevices' }
            Headers = @{}
            Query   = [pscustomobject]@{ tenantFilter = $TenantFilter; Policies = $Policies }
        }
        Invoke-ListIntuneSettingDevices -Request $Request -TriggerMetadata $null
    }

    function New-DeviceStatuses {
        @(
            [pscustomobject]@{ id = 's1'; deviceDisplayName = 'PC1'; userPrincipalName = 'a@contoso.com'; status = 'compliant'; deviceModel = 'Surface'; lastReportedDateTime = '2026-11-01T10:00:00Z' }
            [pscustomobject]@{ id = 's2'; deviceDisplayName = 'PC2'; userPrincipalName = 'b@contoso.com'; status = 'nonCompliant'; deviceModel = 'Latitude'; lastReportedDateTime = '0001-01-01T00:00:00Z' }
        )
    }

    function New-CacheItems {
        param([string]$Type)
        @(New-DeviceStatuses | ForEach-Object { [pscustomobject]@{ RowKey = "$Type-$($_.id)"; Data = ($_ | ConvertTo-Json -Compress) } })
        [pscustomobject]@{ RowKey = "$Type-Count"; DataCount = 2 }
    }
}

Describe 'Invoke-ListIntuneSettingDevices' {
    BeforeEach {
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ defaultDomainName = $script:Partition } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }
    }

    It 'is readable with the MEM read role' {
        (Get-Help Invoke-ListIntuneSettingDevices).Role | Should -Be 'Endpoint.MEM.Read'
    }

    Context 'input validation' {
        BeforeEach {
            Mock -CommandName New-GraphGetRequest -MockWith { }
            Mock -CommandName New-GraphPOSTRequest -MockWith { }
            Mock -CommandName Get-CIPPDbItem -MockWith { }
        }

        It 'rejects <Name>' -ForEach @(
            @{ Name = 'AllTenants'; TenantFilter = 'AllTenants'; Policies = "deviceConfigurations:$script:ConfigId" }
            @{ Name = 'a missing tenant'; TenantFilter = ''; Policies = "deviceConfigurations:$script:ConfigId" }
            @{ Name = 'a missing policy list'; TenantFilter = 'contoso.com'; Policies = '' }
            @{ Name = 'a policy id that is not a GUID'; TenantFilter = 'contoso.com'; Policies = "deviceConfigurations:$script:ConfigId,deviceConfigurations:abc') or (1 eq 1" }
            @{ Name = 'an unknown URLName'; TenantFilter = 'contoso.com'; Policies = "deviceConfigurations:$script:ConfigId,users:$script:ComplianceId" }
            @{ Name = 'an entry without a URLName'; TenantFilter = 'contoso.com'; Policies = $script:ConfigId }
        ) {
            $Response = Invoke-Devices -Policies $Policies -TenantFilter $TenantFilter

            $Response.StatusCode | Should -Be 400
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
        }

        It 'says a single tenant is required for AllTenants' {
            $Response = Invoke-Devices -Policies "deviceConfigurations:$script:ConfigId" -TenantFilter 'AllTenants'

            $Response.Body.Results | Should -Be 'A single tenant is required.'
        }

        It 'names the invalid entries' {
            $Response = Invoke-Devices -Policies "users:$script:ComplianceId"

            $Response.Body.Results | Should -Match "users:$script:ComplianceId"
        }

        It 'accepts exactly 50 policies' {
            $Policies = (1..50 | ForEach-Object { 'WindowsFeatureUpdateProfiles:{0:x8}-0000-4000-8000-000000000000' -f $_ }) -join ','

            $Response = Invoke-Devices -Policies $Policies

            $Response.StatusCode | Should -Be 200
        }

        It 'rejects more than 50 policies before reading any' {
            $Policies = (1..51 | ForEach-Object { 'deviceConfigurations:{0:x8}-0000-4000-8000-000000000000' -f $_ }) -join ','

            $Response = Invoke-Devices -Policies $Policies

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -Be 'Too many policies: 51 requested, at most 50 are allowed per request.'
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
        }

        It 'accepts the URLName and id of every policy family a setting search returns' {
            $Policies = @(foreach ($Definition in Get-CIPPIntunePolicyListDefinitions) {
                    $Prefix = if ($Definition.Id -eq 'ManagedAppPolicies') { 'T_' }
                    "$($Definition.Id):$($Prefix)0d2b7a51-6c1e-4f6a-9d39-1f0a2d0c0a0$($Definition.Id.Length % 10)"
                }) -join ','

            Mock -CommandName New-GraphPOSTRequest -MockWith { [pscustomobject]@{ TotalRowCount = 0; Schema = @(); Values = @() } }

            $Response = Invoke-Devices -Policies $Policies

            $Response.StatusCode | Should -Be 200
            @($Response.Body.Metadata.Warnings) | Should -HaveCount 0
        }
    }

    It 'reads cached device statuses from the tenant partition with the same status text as the live path' {
        $script:UseCache = $true
        Mock -CommandName Get-CIPPDbItem -MockWith { if ($script:UseCache -and $Type -eq "IntuneDeviceConfigurations_$script:ConfigId") { New-CacheItems -Type $Type } }
        Mock -CommandName New-GraphGetRequest -MockWith { New-DeviceStatuses }

        $Cached = Invoke-Devices -Policies "DeviceConfigurations:$script:ConfigId"

        $Cached.StatusCode | Should -Be 200
        $Cached.Body.Results | Should -HaveCount 2
        $Cached.Body.Results.Source | Sort-Object -Unique | Should -Be 'Cache'
        $Cached.Body.Results[0].PolicyId | Should -Be $script:ConfigId
        $Cached.Body.Results[0].URLName | Should -Be 'DeviceConfigurations'
        $Cached.Body.Results[0].Status | Should -Be 'Succeeded'
        $Cached.Body.Results[1].Status | Should -Be 'Non compliant'
        $Cached.Body.Results[1].LastReported | Should -BeNullOrEmpty
        $Cached.Body.Metadata.Warnings | Should -HaveCount 0
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke Get-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Partition -eq $script:Partition }

        $script:UseCache = $false
        $Live = Invoke-Devices -Policies "DeviceConfigurations:$script:ConfigId"

        $Live.Body.Results.Source | Sort-Object -Unique | Should -Be 'Live'
        $Fields = @('PolicyId', 'URLName', 'DeviceName', 'UserPrincipalName', 'Status', 'StatusDetail', 'Platform', 'LastReported')
        ($Cached.Body.Results | Select-Object $Fields | ConvertTo-Json -Compress) | Should -BeExactly ($Live.Body.Results | Select-Object $Fields | ConvertTo-Json -Compress)
    }

    It 'falls back to live deviceStatuses when nothing is cached, without reading user statuses' {
        Mock -CommandName Get-CIPPDbItem -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { New-DeviceStatuses }

        $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

        $Response.Body.Results | Should -HaveCount 2
        $Response.Body.Results[0].Status | Should -Be 'Compliant'
        $Response.Body.Results[0].Source | Should -Be 'Live'
        Should -Invoke Get-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq "IntuneDeviceCompliancePolicies_$script:ComplianceId" }
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*/deviceManagement/deviceCompliancePolicies('$script:ComplianceId')/deviceStatuses" }
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*/userStatuses' }
    }

    Context 'a device with system and user rows under one id' {
        BeforeAll {
            $script:SharedDeviceId = '0d69714d-0000-4000-8000-000000000002'
            function New-DuplicateStatuses {
                @(
                    [pscustomobject]@{ id = "f62b4d46-0000-4000-8000-000000000001_$script:SharedDeviceId"; deviceDisplayName = 'PC1'; userPrincipalName = ''; status = 'remediated'; deviceModel = 'Surface'; lastReportedDateTime = '2026-11-01T10:00:00Z' }
                    [pscustomobject]@{ id = "f62b4d46-0000-4000-8000-000000000001_$script:SharedDeviceId"; deviceDisplayName = 'PC1'; userPrincipalName = 'a@contoso.com'; status = 'compliant'; deviceModel = 'Surface'; lastReportedDateTime = '2026-11-02T10:00:00Z' }
                    [pscustomobject]@{ id = 's2'; deviceDisplayName = 'PC2'; userPrincipalName = 'b@contoso.com'; status = 'nonCompliant'; deviceModel = 'Latitude'; lastReportedDateTime = '2026-11-03T10:00:00Z' }
                )
            }
            function New-FirstWinsCacheItems {
                param([string]$Type)
                $Keys = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($Row in New-DuplicateStatuses) {
                    if ($Keys.Add("$Type-$($Row.id)")) { [pscustomobject]@{ RowKey = "$Type-$($Row.id)"; Data = ($Row | ConvertTo-Json -Compress) } }
                }
                [pscustomobject]@{ RowKey = "$Type-Count"; DataCount = 2 }
            }
        }

        It 'returns the first row only on the live path' {
            Mock -CommandName Get-CIPPDbItem -MockWith { }
            Mock -CommandName New-GraphGetRequest -MockWith { New-DuplicateStatuses }

            $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Response.Body.Results | Should -HaveCount 2
            $Response.Body.Results[0].DeviceName | Should -Be 'PC1'
            $Response.Body.Results[0].UserPrincipalName | Should -Be 'System account'
            $Response.Body.Results[0].Status | Should -Be 'Remediated'
            $Response.Body.Results[1].DeviceName | Should -Be 'PC2'
        }

        It 'returns the same rows from the cache and live' {
            $script:UseCache = $true
            Mock -CommandName Get-CIPPDbItem -MockWith { if ($script:UseCache) { New-FirstWinsCacheItems -Type $Type } }
            Mock -CommandName New-GraphGetRequest -MockWith { New-DuplicateStatuses }

            $Cached = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"
            $script:UseCache = $false
            $Live = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Cached.Body.Results.Source | Sort-Object -Unique | Should -Be 'Cache'
            $Live.Body.Results.Source | Sort-Object -Unique | Should -Be 'Live'
            $Fields = @('PolicyId', 'URLName', 'DeviceName', 'UserPrincipalName', 'Status', 'StatusDetail', 'Platform', 'LastReported')
            ($Cached.Body.Results | Select-Object $Fields | ConvertTo-Json -Compress) | Should -BeExactly ($Live.Body.Results | Select-Object $Fields | ConvertTo-Json -Compress)
        }

        It 'keeps the first row per device for app configurations too' {
            Mock -CommandName Get-CIPPDbItem -MockWith { }
            Mock -CommandName New-GraphGetRequest -MockWith { New-DuplicateStatuses }

            $Response = Invoke-Devices -Policies "MobileAppConfigurations:$script:ConfigId"

            $Response.Body.Results | Should -HaveCount 2
        }
    }

    It 'reads app configuration statuses live from deviceAppManagement' {
        Mock -CommandName Get-CIPPDbItem -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { New-DeviceStatuses }

        $Response = Invoke-Devices -Policies "MobileAppConfigurations:$script:ConfigId"

        $Response.Body.Results | Should -HaveCount 2
        Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -ceq "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations('$script:ConfigId')/deviceStatuses" }
    }

    Context 'device names from the managed device' {
        BeforeAll {
            $script:CachedDeviceId = '0d69714d-945b-4fd8-97a4-b7f98cac2e9a'
            $script:LiveDeviceId = '1e69714d-945b-4fd8-97a4-b7f98cac2e9b'
            function New-UnnamedStatuses {
                @(
                    [pscustomobject]@{ id = "d3214a4e-0000-4000-8000-000000000001_f62b4d46-0000-4000-8000-000000000002_$script:CachedDeviceId"; deviceDisplayName = ''; userPrincipalName = ''; status = 'compliant'; deviceModel = $null; lastReportedDateTime = '0001-01-01T00:00:00Z' }
                    [pscustomobject]@{ id = "d3214a4e-0000-4000-8000-000000000001_f62b4d46-0000-4000-8000-000000000003_$script:LiveDeviceId"; deviceDisplayName = ''; userPrincipalName = 'b@contoso.com'; status = 'nonCompliant'; deviceModel = $null; lastReportedDateTime = '0001-01-01T00:00:00Z' }
                    [pscustomobject]@{ id = 'd3214a4e-0000-4000-8000-000000000001_f62b4d46-0000-4000-8000-000000000004_2f69714d-945b-4fd8-97a4-b7f98cac2e9c'; deviceDisplayName = 'PC3'; userPrincipalName = 'c@contoso.com'; status = 'compliant'; deviceModel = 'Surface'; lastReportedDateTime = '2026-11-01T10:00:00Z' }
                )
            }
            function New-UnnamedCacheItems {
                param([string]$Type)
                foreach ($Row in New-UnnamedStatuses) { [pscustomobject]@{ RowKey = "$Type-$($Row.id)"; Data = ($Row | ConvertTo-Json -Compress) } }
                [pscustomobject]@{ RowKey = "$Type-Count"; DataCount = 3 }
            }
        }

        BeforeEach {
            $script:UseCache = $false
            Mock -CommandName Get-CIPPDbItem -MockWith { if ($script:UseCache) { New-UnnamedCacheItems -Type $Type } }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                if ($Filter -like "*'ManagedDevices-$script:CachedDeviceId'*") {
                    [pscustomobject]@{ PartitionKey = $script:Partition; RowKey = "ManagedDevices-$script:CachedDeviceId"; Data = (@{ id = $script:CachedDeviceId; deviceName = 'DESKTOP-ITCSL4O'; operatingSystem = 'Windows' } | ConvertTo-Json -Compress) }
                }
            }
            Mock -CommandName New-GraphGetRequest -MockWith { New-UnnamedStatuses }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                foreach ($Request in $Requests) {
                    if ($Request.id -eq $script:LiveDeviceId) { [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ id = $script:LiveDeviceId; deviceName = 'LAPTOP-7Q2'; operatingSystem = 'Windows' } } }
                    else { [pscustomobject]@{ id = $Request.id; status = 404; body = [pscustomobject]@{ error = @{ code = 'ResourceNotFound' } } } }
                }
            }
        }

        It 'reads one managed device row per unnamed device from the tenant partition' {
            $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Response.Body.Results | Should -HaveCount 3
            $Response.Body.Results[0].DeviceName | Should -Be 'DESKTOP-ITCSL4O'
            $Response.Body.Results[0].Platform | Should -Be 'Windows'
            $Response.Body.Results[0].LastReported | Should -BeNullOrEmpty
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $Type -eq 'ManagedDevices' }
            Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly
            Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Context -eq 'CippReportingDB' -and
                $Filter -ceq "PartitionKey eq '$script:Partition' and RowKey ge 'ManagedDevices-$script:CachedDeviceId' and RowKey lt 'ManagedDevices-$script:CachedDeviceId.'"
            }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly -ParameterFilter { @($Requests.id) -contains $script:CachedDeviceId }
        }

        It 'escapes the tenant partition in the point read' {
            Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ defaultDomainName = "o'brien.com" } }

            $null = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly -ParameterFilter { $Filter -like "PartitionKey eq 'o''brien.com' and *" }
        }

        It 'looks up names the cache does not hold in one bulk request' {
            $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId,deviceConfigurations:$script:ConfigId"

            @($Response.Body.Results | Where-Object { $_.UserPrincipalName -eq 'b@contoso.com' }).DeviceName | Sort-Object -Unique | Should -Be 'LAPTOP-7Q2'
            Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                @($Requests).Count -eq 1 -and $Requests[0].url -ceq "/deviceManagement/managedDevices/$($script:LiveDeviceId)?`$select=id,deviceName,operatingSystem"
            }
        }

        It 'looks up at most 100 unnamed devices' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                foreach ($i in 1..101) {
                    [pscustomobject]@{ id = 'p_u_{0:x8}-0000-4000-8000-000000000000' -f $i; deviceDisplayName = ''; userPrincipalName = "u$i@contoso.com"; status = 'compliant' }
                }
            }
            Mock -CommandName New-GraphBulkRequest -MockWith { }

            $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Response.Body.Results | Should -HaveCount 101
            Should -Invoke Get-CIPPAzDataTableEntity -Times 100 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).Count -eq 100 }
        }

        It 'leaves the name blank and adds a warning when the lookup fails' {
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'Forbidden' }

            $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Response.StatusCode | Should -Be 200
            $Response.Body.Results | Should -HaveCount 3
            $Response.Body.Results[0].DeviceName | Should -Be 'DESKTOP-ITCSL4O'
            $Response.Body.Results[1].DeviceName | Should -BeNullOrEmpty
            $Response.Body.Metadata.Warnings | Should -HaveCount 1
            $Response.Body.Metadata.Warnings[0] | Should -BeLike '*names*Forbidden'
        }

        It 'falls back to Graph when a point read fails' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { throw 'table unavailable' }

            $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Response.StatusCode | Should -Be 200
            $Response.Body.Results[1].DeviceName | Should -Be 'LAPTOP-7Q2'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).Count -eq 2 }
        }

        It 'labels the row without a user as the system account' {
            $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Response.Body.Results[0].UserPrincipalName | Should -Be 'System account'
            $Response.Body.Results[1].UserPrincipalName | Should -Be 'b@contoso.com'
        }

        It 'leaves names Intune reported untouched' {
            $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Response.Body.Results[2].DeviceName | Should -Be 'PC3'
            $Response.Body.Results[2].Platform | Should -Be 'Surface'
            Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Filter -like '*2f69714d-945b-4fd8-97a4-b7f98cac2e9c*' }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly -ParameterFilter { @($Requests.id) -contains '2f69714d-945b-4fd8-97a4-b7f98cac2e9c' }
        }

        It 'returns the same rows from the cache and live' {
            $script:UseCache = $true
            $Cached = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"
            $script:UseCache = $false
            $Live = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId"

            $Cached.Body.Results.Source | Sort-Object -Unique | Should -Be 'Cache'
            $Live.Body.Results.Source | Sort-Object -Unique | Should -Be 'Live'
            $Fields = @('PolicyId', 'URLName', 'DeviceName', 'UserPrincipalName', 'Status', 'StatusDetail', 'Platform', 'LastReported')
            ($Cached.Body.Results | Select-Object $Fields | ConvertTo-Json -Compress) | Should -BeExactly ($Live.Body.Results | Select-Object $Fields | ConvertTo-Json -Compress)
        }

        It 'fills settings catalog report rows from their <Column>, cached or live' -ForEach @(
            @{ Column = 'IntuneDeviceId' }
            @{ Column = 'DeviceId' }
        ) {
            $Columns = @($Column, 'UserId', 'DeviceName', 'UPN', 'ReportStatus', 'ReportStatus_loc', 'UnifiedPolicyPlatformType_loc', 'PspdpuLastModifiedTimeUtc')
            $Values = @(, @($script:CachedDeviceId, 'u1', '', 'a@contoso.com', 'Succeeded', 'Succeeded', '', '2026-11-01T10:00:00'))
            Mock -CommandName New-GraphPOSTRequest -MockWith {
                [pscustomobject]@{ TotalRowCount = 1; Schema = @($Columns | ForEach-Object { [pscustomobject]@{ Column = $_ } }); Values = $Values }
            }
            $Live = Invoke-Devices -Policies "configurationPolicies:$script:CatalogId"

            Mock -CommandName Get-CIPPDbItem -MockWith {
                $Row = [ordered]@{ id = "$($script:CachedDeviceId)||u1"; IntuneDeviceId = $script:CachedDeviceId }
                for ($i = 1; $i -lt $Columns.Count; $i++) { $Row[$Columns[$i]] = $Values[0][$i] }
                [pscustomobject]@{ RowKey = "$Type-$($Row.id)"; Data = ([pscustomobject]$Row | ConvertTo-Json -Compress) }
                [pscustomobject]@{ RowKey = "$Type-Count"; DataCount = 1 }
            }
            $Cached = Invoke-Devices -Policies "configurationPolicies:$script:CatalogId"

            $Live.Body.Results[0].DeviceName | Should -Be 'DESKTOP-ITCSL4O'
            $Live.Body.Results[0].Platform | Should -Be 'Windows'
            $Live.Body.Results[0].UserPrincipalName | Should -Be 'a@contoso.com'
            $Cached.Body.Results[0].Source | Should -Be 'Cache'
            ($Cached.Body.Results | Select-Object -ExcludeProperty Source | ConvertTo-Json -Compress) |
                Should -Be ($Live.Body.Results | Select-Object -ExcludeProperty Source | ConvertTo-Json -Compress)
        }
    }

    It 'falls back to live when the cache cannot be read' {
        Mock -CommandName Get-CIPPDbItem -MockWith { throw 'table unavailable' }
        Mock -CommandName New-GraphGetRequest -MockWith { New-DeviceStatuses }

        $Response = Invoke-Devices -Policies "deviceConfigurations:$script:ConfigId"

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -HaveCount 2
        $Response.Body.Results[0].Source | Should -Be 'Live'
    }

    It 'falls back to live when a cached row cannot be parsed' {
        Mock -CommandName Get-CIPPDbItem -MockWith { [pscustomobject]@{ RowKey = "$Type-s1"; Data = '{not json' } }
        Mock -CommandName New-GraphGetRequest -MockWith { New-DeviceStatuses }

        $Response = Invoke-Devices -Policies "deviceConfigurations:$script:ConfigId"

        $Response.Body.Results | Should -HaveCount 2
        $Response.Body.Results.Source | Sort-Object -Unique | Should -Be 'Live'
    }

    It 'reads settings catalog devices live from the configuration policy report when the cache has none' {
        Mock -CommandName Get-CIPPDbItem -MockWith { }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            [pscustomobject]@{
                TotalRowCount = 1
                Schema        = @('DeviceName', 'UPN', 'ReportStatus_loc', 'UnifiedPolicyPlatformType_loc', 'PspdpuLastModifiedTimeUtc' | ForEach-Object { [pscustomobject]@{ Column = $_ } })
                Values        = @(, @('PC9', 'c@contoso.com', 'Error', 'Windows10', '2026-11-03T10:00:00'))
            }
        }

        $Response = Invoke-Devices -Policies "configurationPolicies:$script:CatalogId"

        $Response.Body.Results | Should -HaveCount 1
        $Response.Body.Results[0].DeviceName | Should -Be 'PC9'
        $Response.Body.Results[0].Status | Should -Be 'Error'
        $Response.Body.Results[0].Platform | Should -Be 'Windows10'
        $Response.Body.Results[0].Source | Should -Be 'Live'
        Should -Invoke Get-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq "IntuneConfigurationPolicyDevices_$script:CatalogId" }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/getConfigurationPolicyDevicesReport' -and ($body | ConvertFrom-Json).filter -like "*PolicyId eq '$script:CatalogId'*" }
    }

    Context 'settings catalog device report cache' {
        BeforeAll {
            $script:ReportColumns = @('IntuneDeviceId', 'UserId', 'DeviceName', 'UPN', 'ReportStatus', 'ReportStatus_loc', 'UnifiedPolicyPlatformType_loc', 'PspdpuLastModifiedTimeUtc')
            $script:ReportValues = @(
                , @('d1', 'u1', 'PC1', 'a@contoso.com', 'Succeeded', 'Succeeded', 'Windows10', '2026-11-01T10:00:00')
                , @('d1', '00000000-0000-0000-0000-000000000000', 'PC1', '', 'Error', 'Error', 'Windows10', '2026-11-02T10:00:00')
            )
            function New-CatalogCacheItems {
                param([int]$DataCount)
                $Type = "IntuneConfigurationPolicyDevices_$script:CatalogId"
                foreach ($Values in $script:ReportValues | Select-Object -First $DataCount) {
                    $Row = [ordered]@{}
                    for ($i = 0; $i -lt $script:ReportColumns.Count; $i++) { $Row[$script:ReportColumns[$i]] = $Values[$i] }
                    $Row.id = "$($Row.IntuneDeviceId)|$($Row.DeviceName)|$($Row.UserId)"
                    [pscustomobject]@{ RowKey = "$Type-$($Row.id)"; Data = ([pscustomobject]$Row | ConvertTo-Json -Compress) }
                }
                [pscustomobject]@{ RowKey = "$Type-Count"; DataCount = $DataCount }
            }
        }

        BeforeEach {
            Mock -CommandName New-GraphPOSTRequest -MockWith {
                [pscustomobject]@{
                    TotalRowCount = 2
                    Schema        = @($script:ReportColumns | ForEach-Object { [pscustomobject]@{ Column = $_ } })
                    Values        = $script:ReportValues
                }
            }
        }

        It 'reads cached report rows first, with the same rows as live' {
            Mock -CommandName Get-CIPPDbItem -MockWith { New-CatalogCacheItems -DataCount 2 }

            $Cached = Invoke-Devices -Policies "configurationPolicies:$script:CatalogId"

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            $Cached.Body.Results | Should -HaveCount 2
            @($Cached.Body.Results.Source | Select-Object -Unique) | Should -Be @('Cache')

            Mock -CommandName Get-CIPPDbItem -MockWith { }
            $Live = Invoke-Devices -Policies "configurationPolicies:$script:CatalogId"

            @($Live.Body.Results.Source | Select-Object -Unique) | Should -Be @('Live')
            ($Cached.Body.Results | Select-Object -ExcludeProperty Source | ConvertTo-Json -Compress) |
                Should -Be ($Live.Body.Results | Select-Object -ExcludeProperty Source | ConvertTo-Json -Compress)
        }

        It 'treats a cached report with no devices as authoritative' {
            Mock -CommandName Get-CIPPDbItem -MockWith { New-CatalogCacheItems -DataCount 0 }

            $Response = Invoke-Devices -Policies "configurationPolicies:$script:CatalogId"

            $Response.StatusCode | Should -Be 200
            @($Response.Body.Results) | Should -HaveCount 0
            $Response.Body.Metadata.Warnings | Should -BeNullOrEmpty
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'falls back to live when the cache cannot be read' {
            Mock -CommandName Get-CIPPDbItem -MockWith { throw 'table unavailable' }

            $Response = Invoke-Devices -Policies "configurationPolicies:$script:CatalogId"

            $Response.Body.Results | Should -HaveCount 2
            @($Response.Body.Results.Source | Select-Object -Unique) | Should -Be @('Live')
        }
    }

    It 'returns 207 with the rows it could load and a warning for a policy that fails' {
        Mock -CommandName Get-CIPPDbItem -MockWith { }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*deviceConfigurations*' } -MockWith { New-DeviceStatuses }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*deviceCompliancePolicies*' } -MockWith { throw 'Forbidden' }

        $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId, deviceConfigurations:$script:ConfigId"

        $Response.StatusCode | Should -Be 207
        $Response.Body.Results | Should -HaveCount 2
        $Response.Body.Results.PolicyId | Sort-Object -Unique | Should -Be $script:ConfigId
        $Response.Body.Metadata.Warnings | Should -HaveCount 1
        $Response.Body.Metadata.Warnings[0] | Should -Be "Failed to load deployment status for deviceCompliancePolicies $($script:ComplianceId): Forbidden"
    }

    It 'returns 500 when every policy fails' {
        Mock -CommandName Get-CIPPDbItem -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Forbidden' }

        $Response = Invoke-Devices -Policies "deviceCompliancePolicies:$script:ComplianceId, deviceConfigurations:$script:ConfigId"

        $Response.StatusCode | Should -Be 500
        @($Response.Body.Results) | Should -HaveCount 0
        $Response.Body.Metadata.Warnings | Should -HaveCount 2
    }

    It 'returns no rows and no warning for policy types without per-device status' {
        Mock -CommandName Get-CIPPDbItem -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { }

        $Response = Invoke-Devices -Policies "WindowsFeatureUpdateProfiles:$script:ConfigId,ManagedAppPolicies:T_$script:ComplianceId,hardwareConfigurations:$script:CatalogId"

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results) | Should -HaveCount 0
        $Response.Body.Metadata.Warnings | Should -HaveCount 0
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'reads a policy listed twice once' {
        Mock -CommandName Get-CIPPDbItem -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { New-DeviceStatuses }

        $Response = Invoke-Devices -Policies "deviceConfigurations:$script:ConfigId,DeviceConfigurations:$($script:ConfigId.ToUpper())"

        $Response.Body.Results | Should -HaveCount 2
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
    }

    It 'keeps Results an array when no device has the policy' {
        Mock -CommandName Get-CIPPDbItem -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { }

        $Response = Invoke-Devices -Policies "deviceConfigurations:$script:ConfigId"

        ($Response.Body | ConvertTo-Json -Depth 5 -Compress) | Should -BeLike '*"Results":`[`]*'
    }
}

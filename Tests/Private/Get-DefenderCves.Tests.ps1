# Pester tests for get-DefenderCVEs
#
# This is the live-query twin of Set-CIPPDBCacheDefenderCVEs, but it runs on the HTTP worker
# pool via Invoke-ListCVEManagement, so an OOM here lands on user-facing requests. These tests
# lock the row shape that endpoint reads, and the streaming properties that keep peak memory
# down: the raw fetch is streamed and folded record by record, buckets are dropped as rows are
# built without disturbing the iteration, and a failed fetch returns no partial set.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-DefenderCves.ps1'

    # Minimal stubs so Mock has commands to replace during tests.
    function Get-DefenderTvmRaw { param($TenantId, [int]$MaxPages, [switch]$Stream) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . $FunctionPath

    function New-TvmRecord {
        param(
            $cveId = 'CVE-2024-0001',
            $deviceId = 'device-1',
            $deviceName = 'PC-1',
            $softwareVendor = 'microsoft',
            $softwareName = 'edge',
            $softwareVersion = '120.0.0',
            $osVersion = '10.0.19045',
            $severity = 'High',
            $diskPaths = @(),
            $registryPaths = @()
        )
        [pscustomobject]@{
            cveId                        = $cveId
            deviceId                     = $deviceId
            deviceName                   = $deviceName
            osVersion                    = $osVersion
            softwareVendor               = $softwareVendor
            softwareName                 = $softwareName
            softwareVersion              = $softwareVersion
            vulnerabilitySeverityLevel   = $severity
            recommendedSecurityUpdate    = 'KB5034123'
            recommendedSecurityUpdateUrl = 'https://support.microsoft.com/kb/5034123'
            exploitabilityLevel          = 'ExploitIsPublic'
            diskPaths                    = $diskPaths
            registryPaths                = $registryPaths
        }
    }

    # A record the fold cannot bucket: Hashtable.ContainsKey rejects a null key, so this
    # trips the per-record catch instead of producing a row.
    function New-UnbucketableRecord {
        param($deviceId = 'd-bad')
        [pscustomobject]@{ cveId = $null; deviceId = $deviceId }
    }
}

Describe 'get-DefenderCVEs' {
    BeforeEach {
        $script:Tenant = 'contoso.onmicrosoft.com'

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = $Exception.Exception.Message } }
    }

    Context 'returned row shape' {
        It 'returns one row per CVE with every field Invoke-ListCVEManagement reads' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-2024-0001' -deviceId 'd1' -deviceName 'PC-1'
            }

            $Result = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            $Result.Count | Should -Be 1
            $Row = $Result[0]

            $Row.PartitionKey | Should -Be 'CVE-2024-0001'
            $Row.RowKey | Should -Be $script:Tenant
            $Row.customerId | Should -Be $script:Tenant
            $Row.cveId | Should -Be 'CVE-2024-0001'
            $Row.softwareVendor | Should -Be 'microsoft'
            $Row.softwareName | Should -Be 'edge'
            $Row.vulnerabilitySeverityLevel | Should -Be 'High'
            $Row.recommendedSecurityUpdate | Should -Be 'KB5034123'
            $Row.recommendedSecurityUpdateUrl | Should -Be 'https://support.microsoft.com/kb/5034123'
            $Row.exploitabilityLevel | Should -Be 'ExploitIsPublic'
            $Row.deviceCount | Should -Be 1
            # PowerShell 7's -UFormat drops the literal '+' prefix, so the stamp is a bare
            # ISO-8601 UTC string truncated to whole seconds.
            $Row.lastUpdated | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.000Z$'

            $Devices = $Row.deviceDetailsJson | ConvertFrom-Json
            $Devices.deviceId | Should -Be 'd1'
            $Devices.deviceName | Should -Be 'PC-1'
            $Devices.osVersion | Should -Be '10.0.19045'
            $Devices.softwareVersion | Should -Be '120.0.0'
            $Devices.diskPaths | Should -Be ''
            $Devices.registryPaths | Should -Be ''
        }

        It 'joins disk and registry path arrays with semicolons' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -diskPaths @('C:\a\edge.exe', 'C:\b\edge.exe') -registryPaths @('HKLM\SOFTWARE\X')
            }

            $Devices = (@(get-DefenderCVEs -TenantFilter $script:Tenant)[0]).deviceDetailsJson | ConvertFrom-Json
            $Devices.diskPaths | Should -Be 'C:\a\edge.exe;C:\b\edge.exe'
            $Devices.registryPaths | Should -Be 'HKLM\SOFTWARE\X'
        }

        It 'serialises a single device as a JSON object and multiple devices as a JSON array' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-SINGLE' -deviceId 'd1'
                New-TvmRecord -cveId 'CVE-MULTI' -deviceId 'd1'
                New-TvmRecord -cveId 'CVE-MULTI' -deviceId 'd2'
            }

            $Result = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            # Piping the List into ConvertTo-Json (rather than -InputObject) is what produces
            # the bare object for one device. Invoke-ListCVEManagement ConvertFrom-Json's this
            # and foreach's the result, so both shapes have to keep working.
            ($Result | Where-Object { $_.cveId -eq 'CVE-SINGLE' }).deviceDetailsJson | Should -Match '^\{'
            ($Result | Where-Object { $_.cveId -eq 'CVE-MULTI' }).deviceDetailsJson | Should -Match '^\['
        }

        It 'uses the first record of a CVE for the shared software properties' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-2024-0002' -softwareName 'edge' -severity 'High' -deviceId 'd1'
                New-TvmRecord -cveId 'CVE-2024-0002' -softwareName 'chrome' -severity 'Low' -deviceId 'd2'
            }

            $Result = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            $Result.Count | Should -Be 1
            $Result[0].softwareName | Should -Be 'edge'
            $Result[0].vulnerabilitySeverityLevel | Should -Be 'High'
        }

        It 'substitutes empty strings for missing properties' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                [pscustomobject]@{ cveId = 'CVE-BARE'; deviceId = 'd1' }
            }

            $Row = @(get-DefenderCVEs -TenantFilter $script:Tenant)[0]
            $Row.softwareVendor | Should -Be ''
            $Row.softwareName | Should -Be ''
            $Row.vulnerabilitySeverityLevel | Should -Be ''
            $Row.recommendedSecurityUpdate | Should -Be ''
            $Row.recommendedSecurityUpdateUrl | Should -Be ''
            $Row.exploitabilityLevel | Should -Be ''
        }

        It 'stamps every row of a call with the same lastUpdated' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..5) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
            }

            $Result = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            ($Result.lastUpdated | Sort-Object -Unique).Count | Should -Be 1
        }
    }

    Context 'CVE bucketing' {
        It 'merges every record for a CVE into one row and counts the devices' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-A' -deviceId 'd1' -deviceName 'PC-1'
                New-TvmRecord -cveId 'CVE-B' -deviceId 'd1' -deviceName 'PC-1'
                New-TvmRecord -cveId 'CVE-A' -deviceId 'd2' -deviceName 'PC-2'
                New-TvmRecord -cveId 'CVE-A' -deviceId 'd3' -deviceName 'PC-3'
            }

            $Result = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            $Result.Count | Should -Be 2

            $A = $Result | Where-Object { $_.cveId -eq 'CVE-A' }
            $A.deviceCount | Should -Be 3
            (($A.deviceDetailsJson | ConvertFrom-Json).deviceName | Sort-Object) | Should -Be @('PC-1', 'PC-2', 'PC-3')

            ($Result | Where-Object { $_.cveId -eq 'CVE-B' }).deviceCount | Should -Be 1
        }

        It 'never returns the same CVE twice, even when its records are interleaved' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..50) {
                    New-TvmRecord -cveId "CVE-$($i % 5)" -deviceId "d$i" -deviceName "PC-$i"
                }
            }

            $Result = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            # Also covers the emit stage dropping each bucket as it goes: the keys are
            # snapshotted first, so removing while iterating must not skip or repeat a CVE.
            $Result.Count | Should -Be 5
            ($Result.cveId | Sort-Object -Unique).Count | Should -Be 5
            ($Result.deviceCount | Measure-Object -Sum).Sum | Should -Be 50
        }
    }

    Context 'streaming' {
        It 'streams the raw fetch instead of buffering the tenant dataset' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith { New-TvmRecord }

            $null = get-DefenderCVEs -TenantFilter $script:Tenant

            Should -Invoke Get-DefenderTvmRaw -Times 1 -Exactly -ParameterFilter {
                $Stream.IsPresent -and $TenantId -eq 'contoso.onmicrosoft.com'
            }
        }

        It 'folds each record as it arrives rather than after the whole fetch completes' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-A' -deviceId 'd1'
                New-UnbucketableRecord
                throw 'page 3 failed'
            }

            { get-DefenderCVEs -TenantFilter $script:Tenant } | Should -Throw

            # The unbucketable record is only ever logged from inside the fold. A buffered
            # fetch would throw before a single record reached the fold, so this log is the
            # observable proof that stage 1 streams.
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -like 'Allover Build*'
            }
        }
    }

    Context 'empty and failing fetches' {
        It 'warns and returns nothing when the fetch returns no records' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith { }

            $Result = get-DefenderCVEs -TenantFilter $script:Tenant

            $Result | Should -BeNullOrEmpty
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -eq 'No vulnerability data returned from Defender TVM' -and $sev -eq 'Warning'
            }
        }

        It 'reports how many records it skipped and returns nothing when none could be bucketed' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-UnbucketableRecord -deviceId 'd1'
                New-UnbucketableRecord -deviceId 'd2'
            }

            $Result = get-DefenderCVEs -TenantFilter $script:Tenant

            $Result | Should -BeNullOrEmpty
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -eq 'Skipped 2 malformed CVE record(s) during aggregation' -and $sev -eq 'Warning'
            }
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -eq 'No valid CVE records to cache' -and $sev -eq 'Warning'
            }
        }

        It 'still returns the rows it could bucket when only some records are malformed' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-A' -deviceId 'd1'
                New-UnbucketableRecord
                New-TvmRecord -cveId 'CVE-B' -deviceId 'd2'
            }

            $Result = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            $Result.cveId | Sort-Object | Should -Be @('CVE-A', 'CVE-B')
        }

        It 'returns nothing and rethrows when the fetch faults mid-stream' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-A' -deviceId 'd1'
                New-TvmRecord -cveId 'CVE-B' -deviceId 'd2'
                throw 'page 3 failed'
            }

            # Records already folded are discarded with the runspace's stack: the throw unwinds
            # before the emit stage, so the endpoint gets a 500 rather than a partial CVE list
            # it would render as the tenant's full posture.
            { get-DefenderCVEs -TenantFilter $script:Tenant } | Should -Throw

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -like 'CVE Cache Refresh failed*' -and $sev -eq 'Error'
            }
        }
    }
}

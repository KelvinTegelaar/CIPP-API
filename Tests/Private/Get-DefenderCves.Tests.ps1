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

    # A TVM software-inventory row with no CVE. The fold skips these up front (counting them
    # as skipped) rather than trying to bucket a null key, which previously threw and was
    # logged per-record as an 'Allover Build' error.
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

            # The emit stage decides the shape off DeviceCount: one device stays a bare
            # object, several get wrapped as an array - exactly what piping a List through
            # ConvertTo-Json used to produce. Invoke-ListCVEManagement ConvertFrom-Json's
            # this and foreach's the result, so both shapes have to keep working.
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

        It 'serialises each device once as it arrives, not once per row at emit' {
            # Device metadata is folded into its CVE bucket as JSON text on arrival, so the
            # aggregator holds strings rather than a hashtable per (device x software x CVE)
            # record - the single largest thing this function would otherwise retain, and it
            # runs on the HTTP worker pool per user request. One ConvertTo-Json call per
            # incoming record; anything higher means a second serialisation crept back into
            # the emit stage, which is what put two copies of a CVE's devices in memory.
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..30) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
            }

            $script:JsonCalls = 0
            Mock -CommandName ConvertTo-Json -MockWith { $script:JsonCalls++; '{}' }

            $null = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            $script:JsonCalls | Should -Be 30
        }

        It 'emits each row to the pipeline individually rather than as one materialised list' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..25) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
            }

            $Received = [System.Collections.Generic.List[object]]::new()
            get-DefenderCVEs -TenantFilter $script:Tenant | ForEach-Object { $Received.Add($_) }

            # ForEach-Object runs once per pipeline object, so 25 additions of single rows
            # means the caller can fold and release them one at a time. A function that
            # returned a List in one piece would arrive here as 25 items too - PowerShell
            # unrolls it - but a wrapped (,$list) return would land as one 25-element item.
            $Received.Count | Should -Be 25
            $Received | ForEach-Object { @($_).Count | Should -Be 1 }
        }

        It 'skips records with no CVE without throwing or logging an error' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-UnbucketableRecord -deviceId 'd0'
                New-TvmRecord -cveId 'CVE-2024-0009' -deviceId 'd1'
            }

            $Result = @(get-DefenderCVEs -TenantFilter $script:Tenant)

            $Result.cveId | Should -Be 'CVE-2024-0009'
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like 'Allover Build*' }
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Error' }
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

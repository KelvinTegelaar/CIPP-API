# Pester tests for Set-CIPPDBCacheDefenderCVEs
# Locks the cached row shape read by Get-CIPPCVEReport / Invoke-NinjaOneTenantSync, and the
# streaming properties that keep peak memory off the shared CRAFT heap: the raw fetch is
# streamed, rows are emitted per CVE into a single Add-CIPPDbItem pipeline, and nothing is
# written when the fetch fails.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDefenderCVEs.ps1'

    # Minimal stubs so Mock has commands to replace during tests.
    # -Force MUST be declared [switch]: without it the real call sites' trailing -Force binds
    # no argument and the resulting error is swallowed by the function's own catch.
    function Get-DefenderTvmRaw { param($TenantId, [int]$MaxPages, [switch]$Stream) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    # Not a capability (licence) error by default, so the outer catch takes the normal
    # 'CVE Cache Refresh failed' path rather than the skip-and-return branch.
    function Test-CIPPCacheCapabilityError { param($Message) $false }
    function Add-CIPPDbItem {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$TenantFilter,
            [Parameter(Mandatory)][string]$Type,
            [Parameter(Mandatory, ValueFromPipeline)][AllowNull()][AllowEmptyCollection()]$InputObject,
            [switch]$Count,
            [switch]$AddCount,
            [switch]$Append
        )
    }

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
}

Describe 'Set-CIPPDBCacheDefenderCVEs' {
    BeforeEach {
        $script:Tenant = 'contoso.onmicrosoft.com'
        $script:Rows = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Add-CIPPDbItem -MockWith { $script:Rows.Add($InputObject) }
    }

    Context 'cached row shape' {
        It 'emits one row per CVE with every field the frontend reads' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-2024-0001' -deviceId 'd1' -deviceName 'PC-1'
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $script:Rows.Count | Should -Be 1
            $Row = $script:Rows[0]

            $Row.PartitionKey | Should -Be 'CVE-2024-0001'
            $Row.RowKey | Should -Be $script:Tenant
            # Stable RowKey source: Add-CIPPDbItem derives "DefenderCVEs-<id>".
            $Row.id | Should -Be 'CVE-2024-0001'
            $Row.customerId | Should -Be $script:Tenant
            $Row.cveId | Should -Be 'CVE-2024-0001'
            $Row.softwareVendor | Should -Be 'microsoft'
            $Row.softwareName | Should -Be 'edge'
            $Row.softwareVersion | Should -Be '120.0.0'
            $Row.vulnerabilitySeverityLevel | Should -Be 'High'
            $Row.exploitabilityLevel | Should -Be 'ExploitIsPublic'
            $Row.deviceCount | Should -Be 1
            # PowerShell 7's -UFormat drops the literal '+' prefix, so the stored stamp is
            # a bare ISO-8601 UTC string truncated to whole seconds.
            $Row.lastUpdated | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.000Z$'

            # Dropped fields are no longer stored.
            $Row.PSObject.Properties.Name | Should -Not -Contain 'recommendedSecurityUpdate'
            $Row.PSObject.Properties.Name | Should -Not -Contain 'recommendedSecurityUpdateUrl'

            # Minimal per-device payload: id and name only.
            $Devices = $Row.deviceDetailsJson | ConvertFrom-Json
            $Devices.deviceId | Should -Be 'd1'
            $Devices.deviceName | Should -Be 'PC-1'
            $Devices.PSObject.Properties.Name | Should -Not -Contain 'osVersion'
            $Devices.PSObject.Properties.Name | Should -Not -Contain 'diskPaths'
            $Devices.PSObject.Properties.Name | Should -Not -Contain 'registryPaths'
        }

        It 'serialises a single device as a JSON object and multiple devices as a JSON array' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-SINGLE' -deviceId 'd1'
                New-TvmRecord -cveId 'CVE-MULTI' -deviceId 'd1'
                New-TvmRecord -cveId 'CVE-MULTI' -deviceId 'd2'
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $Single = $script:Rows | Where-Object { $_.cveId -eq 'CVE-SINGLE' }
            $Multi = $script:Rows | Where-Object { $_.cveId -eq 'CVE-MULTI' }

            # Piping the List into ConvertTo-Json (rather than -InputObject) is what produces
            # the bare object for one device. Both consumers rely on this shape.
            $Single.deviceDetailsJson | Should -Match '^\{'
            $Multi.deviceDetailsJson | Should -Match '^\['
        }

        It 'uses the first record of a CVE for the shared software properties' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-2024-0002' -softwareName 'edge' -severity 'High' -deviceId 'd1'
                New-TvmRecord -cveId 'CVE-2024-0002' -softwareName 'chrome' -severity 'Low' -deviceId 'd2'
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $script:Rows.Count | Should -Be 1
            $script:Rows[0].softwareName | Should -Be 'edge'
            $script:Rows[0].vulnerabilitySeverityLevel | Should -Be 'High'
        }

        It 'substitutes empty strings for missing properties' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                [pscustomobject]@{ cveId = 'CVE-BARE'; deviceId = 'd1' }
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $Row = $script:Rows[0]
            $Row.softwareVendor | Should -Be ''
            $Row.softwareName | Should -Be ''
            $Row.softwareVersion | Should -Be ''
            $Row.vulnerabilitySeverityLevel | Should -Be ''
            $Row.exploitabilityLevel | Should -Be ''
        }

        It 'counts a device once and stores it once when the same device reports the CVE across several software packages' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-DEDUP' -deviceId 'd1' -deviceName 'PC-1' -softwareName 'edge'
                New-TvmRecord -cveId 'CVE-DEDUP' -deviceId 'd1' -deviceName 'PC-1' -softwareName 'chrome'
                New-TvmRecord -cveId 'CVE-DEDUP' -deviceId 'd2' -deviceName 'PC-2' -softwareName 'edge'
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $script:Rows.Count | Should -Be 1
            $script:Rows[0].deviceCount | Should -Be 2
            (($script:Rows[0].deviceDetailsJson | ConvertFrom-Json).deviceId | Sort-Object) | Should -Be @('d1', 'd2')
        }

        It 'skips software-inventory rows with no CVE without throwing or logging an error' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                [pscustomobject]@{ cveId = $null; deviceId = 'd0'; deviceName = 'PC-0' }
                New-TvmRecord -cveId 'CVE-2024-0009' -deviceId 'd1'
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $script:Rows.Count | Should -Be 1
            $script:Rows[0].cveId | Should -Be 'CVE-2024-0009'
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Error' }
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

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $script:Rows.Count | Should -Be 2

            $A = $script:Rows | Where-Object { $_.cveId -eq 'CVE-A' }
            $A.deviceCount | Should -Be 3
            (($A.deviceDetailsJson | ConvertFrom-Json).deviceName | Sort-Object) | Should -Be @('PC-1', 'PC-2', 'PC-3')

            $B = $script:Rows | Where-Object { $_.cveId -eq 'CVE-B' }
            $B.deviceCount | Should -Be 1
        }

        It 'never emits the same CVE twice, even when its records are interleaved' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..50) {
                    New-TvmRecord -cveId "CVE-$($i % 5)" -deviceId "d$i" -deviceName "PC-$i"
                }
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $script:Rows.Count | Should -Be 5
            ($script:Rows.cveId | Sort-Object -Unique).Count | Should -Be 5
            ($script:Rows.deviceCount | Measure-Object -Sum).Sum | Should -Be 50
        }
    }

    Context 'streaming' {
        It 'streams the raw fetch instead of buffering the tenant dataset' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith { New-TvmRecord }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            Should -Invoke Get-DefenderTvmRaw -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
        }

        It 'feeds Add-CIPPDbItem one row at a time rather than a materialised list' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..25) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            # Pester runs the mock body once per pipeline item, so 25 invocations means 25
            # individually piped rows. A materialised $Entities list handed over as one
            # argument would show a single invocation holding all 25.
            Should -Invoke Add-CIPPDbItem -Times 25 -Exactly
            $script:Rows.Count | Should -Be 25
            $script:Rows | ForEach-Object { @($_).Count | Should -Be 1 }
        }

        It 'stops feeding rows as soon as the consumer faults' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..30) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
            }

            Mock -CommandName Add-CIPPDbItem -MockWith {
                $script:Rows.Add($InputObject)
                if ($script:Rows.Count -ge 3) { throw 'downstream failure' }
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            $script:Rows.Count | Should -Be 3
        }

        It 'serialises each device once as it arrives, not once per row at emit' {
            # Device metadata is folded into its CVE bucket as JSON text on arrival, so the
            # aggregator holds strings rather than a hashtable per (device x software x CVE)
            # record - the single largest thing this job used to retain on a big tenant.
            #
            # This assertion replaced one that counted ConvertTo-Json calls to prove the emit
            # stage was lazy. That proxy only worked while row building was the only caller of
            # ConvertTo-Json; now the fold does the serialising and the count reflects records
            # in, not rows out. Emit-stage laziness is still enforced structurally by the
            # `& { foreach ... } | Add-CIPPDbItem` pipeline and observed by the fault test
            # above, but note it is no longer possible to distinguish a lazy producer from one
            # that pre-builds every row and then pipes them, because nothing per-row is mockable.
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..30) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
            }

            $script:JsonCalls = 0
            Mock -CommandName ConvertTo-Json -MockWith { $script:JsonCalls++; '{}' }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            # One per incoming record. Anything higher means a second serialisation crept back
            # into the emit stage, which is what put two copies of a CVE's devices in memory.
            $script:JsonCalls | Should -Be 30
        }

        It 'passes AddCount exactly once so the stored count is the run total' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                foreach ($i in 1..10) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
            }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            # Every row must ride the same invocation: Add-CIPPDbItem writes DefenderCVEs-Count
            # and runs its orphan cleanup once per pipeline, in its end block.
            Should -Invoke Add-CIPPDbItem -Times 10 -Exactly -ParameterFilter {
                $AddCount.IsPresent -and $Type -eq 'DefenderCVEs' -and $TenantFilter -eq 'contoso.onmicrosoft.com'
            }
        }
    }

    Context 'empty and failing fetches' {
        It 'warns and writes nothing when the fetch returns no records' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith { }

            Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

            Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -eq 'No vulnerability data returned from Defender TVM' -and $sev -eq 'Warning'
            }
        }

        It 'writes nothing and rethrows when the fetch faults mid-stream' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith {
                New-TvmRecord -cveId 'CVE-A' -deviceId 'd1'
                New-TvmRecord -cveId 'CVE-B' -deviceId 'd2'
                throw 'page 3 failed'
            }

            { Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant } | Should -Throw

            # Records already folded into the aggregator are discarded with the runspace's
            # stack: the throw unwinds before the emit stage, so no partial row set is cached.
            Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -like 'CVE Cache Refresh failed*' -and $sev -eq 'Error'
            }
        }

        It 'logs and swallows a write failure without rethrowing' {
            Mock -CommandName Get-DefenderTvmRaw -MockWith { New-TvmRecord }
            Mock -CommandName Add-CIPPDbItem -MockWith { throw 'table unavailable' }

            { Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant } | Should -Not -Throw

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -like 'CVE Cache failed*' -and $sev -eq 'Error'
            }
        }
    }
}

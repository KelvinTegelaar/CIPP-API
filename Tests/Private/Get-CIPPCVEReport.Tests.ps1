# Pester tests for Get-CIPPCVEReport
#
# This is the report-database read path behind Invoke-ListCVEManagement (UseReportDB and
# AllTenants). It folds cached rows one at a time - each row's Data blob is parsed and merged
# before the next is touched - so the parsed object graphs never all exist at once on the HTTP
# worker pool's shared heap. These tests lock the response shape the frontend renders and the
# tenant-validation / exception-merge semantics.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPCVEReport.ps1'

    # Minimal stubs so Mock has commands to replace during tests.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . $FunctionPath

    # A cached row exactly as Add-CIPPDbItem stores what Set-CIPPDBCacheDefenderCVEs emits:
    # the table row is keyed by tenant, and the CVE payload lives in the Data JSON with the
    # CVE id as ITS PartitionKey.
    function New-CveRow {
        param(
            $CveId = 'CVE-2024-0001',
            $Tenant = 'contoso.onmicrosoft.com',
            $Devices = @(@{ deviceId = 'd1'; deviceName = 'PC-1'; osVersion = '10.0.19045'; softwareVersion = '120.0.0'; diskPaths = ''; registryPaths = '' }),
            $LastUpdated = '2026-08-12T00:00:00.000Z'
        )
        $Payload = @{
            PartitionKey                 = $CveId
            RowKey                       = $Tenant
            customerId                   = $Tenant
            cveId                        = $CveId
            softwareVendor               = 'microsoft'
            softwareName                 = 'edge'
            vulnerabilitySeverityLevel   = 'High'
            recommendedSecurityUpdate    = 'KB5034123'
            recommendedSecurityUpdateUrl = 'https://support.microsoft.com/kb/5034123'
            exploitabilityLevel          = 'ExploitIsPublic'
            deviceCount                  = @($Devices).Count
            # Piped, not -InputObject: one device stays a bare object, several become an
            # array - the exact shape the collector writes.
            deviceDetailsJson            = [string]($Devices | ConvertTo-Json -Compress)
            lastUpdated                  = $LastUpdated
        }
        [pscustomobject]@{
            PartitionKey = $Tenant
            RowKey       = "DefenderCVEs-$([guid]::NewGuid())"
            Data         = [string]($Payload | ConvertTo-Json -Depth 100 -Compress)
            Type         = 'DefenderCVEs'
        }
    }

    function New-CountRow {
        param($Tenant = 'contoso.onmicrosoft.com')
        [pscustomobject]@{
            PartitionKey = $Tenant
            RowKey       = 'DefenderCVEs-Count'
            DataCount    = 1
            Type         = 'DefenderCVEs'
        }
    }
}

Describe 'Get-CIPPCVEReport' {
    BeforeEach {
        $script:Tenant = 'contoso.onmicrosoft.com'

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Get-Tenants -MockWith {
            @([pscustomobject]@{ defaultDomainName = 'contoso.onmicrosoft.com' })
        }
    }

    Context 'single tenant' {
        It 'returns one aggregated entry per CVE with every field the frontend reads' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                New-CveRow -CveId 'CVE-B' -Devices @(
                    @{ deviceId = 'd1'; deviceName = 'PC-1'; osVersion = ''; softwareVersion = ''; diskPaths = 'C:\a\edge.exe'; registryPaths = 'HKLM\SOFTWARE\X' }
                    @{ deviceId = 'd2'; deviceName = 'PC-2'; osVersion = ''; softwareVersion = ''; diskPaths = ''; registryPaths = '' }
                )
                New-CveRow -CveId 'CVE-A'
                New-CountRow
            }

            $Result = @(Get-CIPPCVEReport -TenantFilter $script:Tenant)

            # Sorted by cveId, count row ignored.
            $Result.Count | Should -Be 2
            $Result[0].cveId | Should -Be 'CVE-A'
            $Result[1].cveId | Should -Be 'CVE-B'

            $B = $Result[1]
            $B.vulnerabilitySeverityLevel | Should -Be 'High'
            $B.exploitabilityLevel | Should -Be 'ExploitIsPublic'
            $B.softwareName | Should -Be 'edge'
            $B.softwareVendor | Should -Be 'microsoft'
            $B.deviceCount | Should -Be 2
            $B.tenantCount | Should -Be 1
            @($B.affectedTenants).customerId | Should -Be @($script:Tenant)
            (@($B.affectedDevices).deviceName | Sort-Object) | Should -Be @('PC-1', 'PC-2')
            @($B.diskPaths).Count | Should -Be 1
            @($B.diskPaths)[0].diskPaths | Should -Be 'C:\a\edge.exe'
            @($B.registryPaths)[0].registryPaths | Should -Be 'HKLM\SOFTWARE\X'
            $B.exceptionStatus | Should -Be 'None'
            $B.hasException | Should -BeFalse
            # ConvertFrom-Json turns the ISO stamp in the Data blob into a DateTime, so the
            # report carries the instant, not the original string formatting.
            ([datetime]$B.cacheTimeStamp).ToUniversalTime().Ticks | Should -Be ([datetime]::Parse('2026-08-12T00:00:00Z', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)).Ticks
        }

        It 'deduplicates devices by name within a row' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                New-CveRow -CveId 'CVE-A' -Devices @(
                    @{ deviceId = 'd1'; deviceName = 'PC-1'; osVersion = ''; softwareVersion = '1.0'; diskPaths = ''; registryPaths = '' }
                    @{ deviceId = 'd1'; deviceName = 'PC-1'; osVersion = ''; softwareVersion = '2.0'; diskPaths = ''; registryPaths = '' }
                )
            }

            $Result = @(Get-CIPPCVEReport -TenantFilter $script:Tenant)

            $Result[0].deviceCount | Should -Be 1
            @($Result[0].affectedDevices).Count | Should -Be 1
        }

        It 'returns a bare empty array when the cache only holds the count row' {
            Mock -CommandName Get-CIPPDbItem -MockWith { New-CountRow }

            $Result = Get-CIPPCVEReport -TenantFilter $script:Tenant

            @($Result).Count | Should -Be 0
        }
    }

    Context 'AllTenants' {
        BeforeEach {
            Mock -CommandName Get-Tenants -MockWith {
                @(
                    [pscustomobject]@{ defaultDomainName = 'contoso.onmicrosoft.com' }
                    [pscustomobject]@{ defaultDomainName = 'fabrikam.onmicrosoft.com' }
                )
            }
        }

        It 'merges the same CVE across tenants into one entry' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                New-CveRow -CveId 'CVE-A' -Tenant 'contoso.onmicrosoft.com'
                New-CveRow -CveId 'CVE-A' -Tenant 'fabrikam.onmicrosoft.com' -Devices @(
                    @{ deviceId = 'd9'; deviceName = 'PC-9'; osVersion = ''; softwareVersion = ''; diskPaths = ''; registryPaths = '' }
                )
            }

            $Result = @(Get-CIPPCVEReport -TenantFilter 'AllTenants')

            $Result.Count | Should -Be 1
            $Result[0].tenantCount | Should -Be 2
            $Result[0].deviceCount | Should -Be 2
            (@($Result[0].affectedTenants).customerId | Sort-Object) | Should -Be @('contoso.onmicrosoft.com', 'fabrikam.onmicrosoft.com')
        }

        It 'drops rows belonging to tenants that are no longer managed' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                New-CveRow -CveId 'CVE-A' -Tenant 'contoso.onmicrosoft.com'
                New-CveRow -CveId 'CVE-ORPHAN' -Tenant 'departed.onmicrosoft.com'
            }

            $Result = @(Get-CIPPCVEReport -TenantFilter 'AllTenants')

            $Result.Count | Should -Be 1
            $Result[0].cveId | Should -Be 'CVE-A'
        }
    }

    Context 'exceptions' {
        It 'marks a CVE All when an ALL-scoped exception matches and Partial for tenant-scoped' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                New-CveRow -CveId 'CVE-GLOBAL'
                New-CveRow -CveId 'CVE-LOCAL'
            }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @(
                    [pscustomobject]@{ cveId = 'CVE-GLOBAL'; customerId = 'ALL'; exceptionType = 'RiskAccepted'; exceptionSource = 'CIPP'; exceptionComment = 'global'; exceptionCreatedBy = 'admin'; exceptionReadableDate = 'today'; exceptionExpiry = '' }
                    [pscustomobject]@{ cveId = 'CVE-LOCAL'; customerId = 'contoso.onmicrosoft.com'; exceptionType = 'Mitigated'; exceptionSource = 'CIPP'; exceptionComment = 'local'; exceptionCreatedBy = 'admin'; exceptionReadableDate = 'today'; exceptionExpiry = '' }
                )
            }

            $Result = @(Get-CIPPCVEReport -TenantFilter $script:Tenant)

            $Global = $Result | Where-Object { $_.cveId -eq 'CVE-GLOBAL' }
            $Global.exceptionStatus | Should -Be 'All'
            $Global.hasException | Should -BeTrue
            $Global.exceptionType.exceptionType | Should -Be 'RiskAccepted'

            $Local = $Result | Where-Object { $_.cveId -eq 'CVE-LOCAL' }
            $Local.exceptionStatus | Should -Be 'Partial'
            $Local.exceptionComment.exceptionComment | Should -Be 'local'
        }

        It 'ignores exceptions scoped to tenants outside the filter' {
            Mock -CommandName Get-CIPPDbItem -MockWith { New-CveRow -CveId 'CVE-A' }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{ cveId = 'CVE-A'; customerId = 'fabrikam.onmicrosoft.com'; exceptionType = 'Mitigated'; exceptionSource = 'CIPP'; exceptionComment = 'other tenant'; exceptionCreatedBy = 'admin'; exceptionReadableDate = 'today'; exceptionExpiry = '' })
            }

            $Result = @(Get-CIPPCVEReport -TenantFilter $script:Tenant)

            $Result[0].exceptionStatus | Should -Be 'None'
            $Result[0].hasException | Should -BeFalse
        }
    }

    Context 'failures' {
        It 'logs and rethrows when the cache read fails' {
            Mock -CommandName Get-CIPPDbItem -MockWith { throw 'table unavailable' }

            { Get-CIPPCVEReport -TenantFilter $script:Tenant } | Should -Throw

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $message -like 'Failed to generate CVE report*' -and $sev -eq 'Error'
            }
        }
    }
}

# Pester tests for Invoke-ListCVEManagement
#
# The live branch merges get-DefenderCVEs output into the response body. That row set is the
# biggest object in the request for a large tenant, and this runs on the HTTP worker pool which
# shares the container's managed heap with the background pool, so these lock both the merged
# response shape and the property that keeps it bounded: the fetch is piped into the merge
# rather than assigned, so each row is collectable once merged.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListCVEManagement.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListCVEManagement.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    # The function uses the bare [HttpStatusCode], as ~600 other entrypoints do. That resolves
    # in the Functions host but not in a plain runspace, so register the accelerator here rather
    # than fully qualifying the source against the house style.
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Get-DefenderCVEs { param($TenantFilter) }
    function Get-CIPPCVEReport { param($TenantFilter) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }

    . $FunctionPath

    function New-CveRequest {
        param($TenantFilter = 'contoso.onmicrosoft.com', $UseReportDB)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListCVEManagement' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]@{ tenantFilter = $TenantFilter; UseReportDB = $UseReportDB }
        }
    }

    # One row per CVE per tenant, matching what get-DefenderCVEs returns.
    function New-CveRow {
        param(
            $cveId = 'CVE-2024-0001',
            $customerId = 'contoso.onmicrosoft.com',
            $severity = 'High',
            $devices = @(@{ deviceName = 'PC-1'; diskPaths = 'C:\a\edge.exe'; registryPaths = 'HKLM\SOFTWARE\X' })
        )
        @{
            PartitionKey               = $cveId
            RowKey                     = $customerId
            customerId                 = $customerId
            cveId                      = $cveId
            vulnerabilitySeverityLevel = $severity
            exploitabilityLevel        = 'ExploitIsPublic'
            softwareName               = 'edge'
            softwareVendor             = 'microsoft'
            deviceCount                = @($devices).Count
            deviceDetailsJson          = ($devices | ConvertTo-Json -Compress)
            lastUpdated                = '2026-07-31T00:00:00.000Z'
        }
    }
}

Describe 'Invoke-ListCVEManagement' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'CveExceptions' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.onmicrosoft.com' }
        }
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
    }

    Context 'live branch response shape' {
        It 'returns one entry per CVE with the device details unpacked' {
            Mock -CommandName Get-DefenderCVEs -MockWith {
                New-CveRow -cveId 'CVE-2024-0002' -severity 'Low' -devices @(
                    @{ deviceName = 'PC-1'; diskPaths = 'C:\a\edge.exe'; registryPaths = 'HKLM\SOFTWARE\X' }
                    @{ deviceName = 'PC-2'; diskPaths = ''; registryPaths = '' }
                )
                New-CveRow -cveId 'CVE-2024-0001'
            }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Count | Should -Be 2
            # Sorted by cveId on the way out.
            $Response.Body.cveId | Should -Be @('CVE-2024-0001', 'CVE-2024-0002')

            $Two = $Response.Body | Where-Object cveId -EQ 'CVE-2024-0002'
            $Two.vulnerabilitySeverityLevel | Should -Be 'Low'
            $Two.exploitabilityLevel | Should -Be 'ExploitIsPublic'
            $Two.softwareName | Should -Be 'edge'
            $Two.softwareVendor | Should -Be 'microsoft'
            $Two.deviceCount | Should -Be 2
            $Two.tenantCount | Should -Be 1
            $Two.affectedDevices.deviceName | Should -Be @('PC-1', 'PC-2')
            $Two.affectedTenants.customerId | Should -Be @('contoso.onmicrosoft.com')
            $Two.cacheTimeStamp | Should -Be '2026-07-31T00:00:00.000Z'
            # Only the device that actually carries paths contributes a path entry.
            $Two.diskPaths.deviceName | Should -Be @('PC-1')
            $Two.registryPaths.registryPaths | Should -Be @('HKLM\SOFTWARE\X')
            $Two.hasException | Should -BeFalse
            $Two.exceptionStatus | Should -Be 'None'
        }

        It 'deduplicates devices by name within a CVE' {
            Mock -CommandName Get-DefenderCVEs -MockWith {
                New-CveRow -devices @(
                    @{ deviceName = 'PC-1'; diskPaths = 'C:\a'; registryPaths = '' }
                    @{ deviceName = 'PC-1'; diskPaths = 'C:\b'; registryPaths = '' }
                    @{ deviceName = 'PC-2'; diskPaths = ''; registryPaths = '' }
                )
            }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest) -TriggerMetadata $null

            $Response.Body[0].deviceCount | Should -Be 2
        }

        It 'returns a bare empty array when the tenant has no CVEs' {
            Mock -CommandName Get-DefenderCVEs -MockWith { }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest) -TriggerMetadata $null

            # Not an HttpResponseContext - the pre-existing early return hands back @() directly.
            $Response | Should -BeNullOrEmpty
            $Response -is [HttpResponseContext] | Should -BeFalse
        }

        It 'attaches exceptions that match the tenant and ones scoped to ALL' {
            Mock -CommandName Get-DefenderCVEs -MockWith {
                New-CveRow -cveId 'CVE-ALL'
                New-CveRow -cveId 'CVE-TENANT'
                New-CveRow -cveId 'CVE-NONE'
            }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @(
                    [pscustomobject]@{ cveId = 'CVE-ALL'; customerId = 'ALL'; exceptionType = 'Accepted'; exceptionComment = 'risk accepted'; exceptionCreatedBy = 'zac'; exceptionReadableDate = '2026-07-01'; exceptionExpiry = '2027-07-01' }
                    [pscustomobject]@{ cveId = 'CVE-TENANT'; customerId = 'contoso.onmicrosoft.com'; exceptionType = 'Mitigated'; exceptionComment = 'patched'; exceptionCreatedBy = 'zac'; exceptionReadableDate = '2026-07-02'; exceptionExpiry = '2027-07-02' }
                    [pscustomobject]@{ cveId = 'CVE-NONE'; customerId = 'other.onmicrosoft.com'; exceptionType = 'Accepted'; exceptionComment = 'not ours'; exceptionCreatedBy = 'someone'; exceptionReadableDate = '2026-07-03'; exceptionExpiry = '2027-07-03' }
                )
            }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest) -TriggerMetadata $null

            $All = $Response.Body | Where-Object cveId -EQ 'CVE-ALL'
            $All.hasException | Should -BeTrue
            $All.exceptionStatus | Should -Be 'All'
            $All.exceptionComment.exceptionComment | Should -Be 'risk accepted'
            $All.exceptionDate.exceptionDate | Should -Be '2026-07-01'

            $Tenant = $Response.Body | Where-Object cveId -EQ 'CVE-TENANT'
            $Tenant.hasException | Should -BeTrue
            $Tenant.exceptionStatus | Should -Be 'Partial'
            $Tenant.exceptionType.exceptionType | Should -Be 'Mitigated'

            # Scoped to a tenant this request is not for, so it must not attach.
            ($Response.Body | Where-Object cveId -EQ 'CVE-NONE').hasException | Should -BeFalse
        }
    }

    Context 'streaming the CVE fetch into the merge' {
        It 'merges each row as it arrives instead of materialising the whole set first' {
            Mock -CommandName Get-DefenderCVEs -MockWith {
                New-CveRow -cveId 'CVE-1'
                New-CveRow -cveId 'CVE-2'
                New-CveRow -cveId 'CVE-3'
                throw 'TVM fetch failed on page 4'
            }

            # ConvertFrom-Json runs once per row as that row is merged. Assigning the fetch to a
            # variable would throw before a single row was merged and leave this at 0; piping it
            # means the first three rows are already merged when the fault arrives.
            $script:JsonCalls = 0
            Mock -CommandName ConvertFrom-Json -MockWith {
                $script:JsonCalls++
                [pscustomobject]@{ deviceName = 'PC-1'; diskPaths = ''; registryPaths = '' }
            }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest) -TriggerMetadata $null

            $script:JsonCalls | Should -Be 3
            # The fault still surfaces as a 500 rather than a partial CVE list the frontend would
            # render as the tenant's full posture.
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        }

        It 'requests the CVE set exactly once for the tenant in the query' {
            Mock -CommandName Get-DefenderCVEs -MockWith { New-CveRow }

            $null = Invoke-ListCVEManagement -Request (New-CveRequest -TenantFilter 'fabrikam.onmicrosoft.com') -TriggerMetadata $null

            Should -Invoke Get-DefenderCVEs -Times 1 -Exactly -ParameterFilter {
                $TenantFilter -eq 'fabrikam.onmicrosoft.com'
            }
        }
    }

    Context 'tenant scope enforcement (AnyTenant)' {
        It 'refuses the live path for a tenant the restricted caller cannot resolve' {
            Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
            # Scope-narrowed Get-Tenants: the requested tenant resolves to nothing.
            Mock -CommandName Get-Tenants -MockWith { }
            Mock -CommandName Get-DefenderCVEs -MockWith { New-CveRow }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest -TenantFilter 'other.onmicrosoft.com') -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            Should -Invoke Get-DefenderCVEs -Times 0 -Exactly
        }

        It 'serves the live path when the restricted caller is scoped to the tenant' {
            Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
            Mock -CommandName Get-DefenderCVEs -MockWith { New-CveRow }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke Get-DefenderCVEs -Times 1 -Exactly
        }
    }

    Context 'reporting database branch' {
        It 'reads the cache and never queries Defender live when UseReportDB is true' {
            Mock -CommandName Get-CIPPCVEReport -MockWith { @([pscustomobject]@{ cveId = 'CVE-CACHED' }) }
            Mock -CommandName Get-DefenderCVEs -MockWith { throw 'live TVM should not be called' }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest -UseReportDB 'true') -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.cveId | Should -Be @('CVE-CACHED')
            Should -Invoke Get-DefenderCVEs -Times 0 -Exactly
        }

        It 'forces the cache for AllTenants, which the live single-tenant path cannot serve' {
            Mock -CommandName Get-CIPPCVEReport -MockWith { @([pscustomobject]@{ cveId = 'CVE-CACHED' }) }
            Mock -CommandName Get-DefenderCVEs -MockWith { throw 'live TVM should not be called' }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest -TenantFilter 'AllTenants') -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke Get-CIPPCVEReport -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'AllTenants' }
        }

        It 'returns 500 when the cache read fails' {
            Mock -CommandName Get-CIPPCVEReport -MockWith { throw 'table unavailable' }

            $Response = Invoke-ListCVEManagement -Request (New-CveRequest -UseReportDB 'true') -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        }
    }
}

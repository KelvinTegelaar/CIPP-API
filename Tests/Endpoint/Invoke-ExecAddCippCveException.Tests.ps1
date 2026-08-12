# Pester tests for Invoke-ExecAddCippCveException
#
# The AllAffected branch walks the whole DefenderCVEs cache to find which tenants hold the
# CVE. It shipped broken once (`| -Filter` mid-pipeline, a runtime error the catch turned
# into a 500) with nothing covering it, so these tests lock each applyTo resolution and the
# memory property of the fixed branch: rows are substring-probed and only candidates are
# deserialised, so the whole cache is never held parsed at once.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAddCippCveException.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecAddCippCveException.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }

    . $FunctionPath

    function New-ExceptionRequest {
        param(
            $CveId = 'CVE-2024-0001',
            $ApplyTo = 'Global',
            $TenantFilter = 'contoso.onmicrosoft.com'
        )
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAddCippCveException' }
            Headers = @{ 'x-ms-client-principal-name' = 'admin@partner.com' }
            Query   = [pscustomobject]@{ tenantFilter = $TenantFilter }
            Body    = [pscustomobject]@{
                cveId         = $CveId
                exceptionType = 'RiskAccepted'
                applyTo       = $ApplyTo
                justification = 'accepted by customer'
            }
        }
    }

    # A cached row exactly as Add-CIPPDbItem stores what Set-CIPPDBCacheDefenderCVEs emits:
    # keyed by tenant, CVE payload inside the Data JSON.
    function New-CachedCveRow {
        param($CveId, $Tenant)
        $Payload = @{
            PartitionKey      = $CveId
            RowKey            = $Tenant
            customerId        = $Tenant
            cveId             = $CveId
            deviceCount       = 1
            deviceDetailsJson = '{"deviceName":"PC-1"}'
        }
        [pscustomobject]@{
            PartitionKey = $Tenant
            RowKey       = "DefenderCVEs-$([guid]::NewGuid())"
            Data         = [string]($Payload | ConvertTo-Json -Depth 100 -Compress)
            Type         = 'DefenderCVEs'
        }
    }
}

Describe 'Invoke-ExecAddCippCveException' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written.AddRange(@($Entity)) }
        Mock -CommandName Get-CIPPDbItem -MockWith { @() }
    }

    Context 'AllAffected' {
        It 'writes one exception per tenant holding the CVE and ignores the rest of the cache' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                New-CachedCveRow -CveId 'CVE-2024-0001' -Tenant 'contoso.onmicrosoft.com'
                New-CachedCveRow -CveId 'CVE-2024-0001' -Tenant 'fabrikam.onmicrosoft.com'
                New-CachedCveRow -CveId 'CVE-2024-9999' -Tenant 'tailspin.onmicrosoft.com'
                [pscustomobject]@{ PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'DefenderCVEs-Count'; DataCount = 3 }
            }

            $Response = Invoke-ExecAddCippCveException -Request (New-ExceptionRequest -ApplyTo 'AllAffected') -TriggerMetadata @{}

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $Response.Body.TenantsAffected | Should -Be 2

            (@($script:Written).RowKey | Sort-Object) | Should -Be @('contoso.onmicrosoft.com', 'fabrikam.onmicrosoft.com')
            @($script:Written) | ForEach-Object {
                $_.PartitionKey | Should -Be 'CVE-2024-0001'
                $_.exceptionType | Should -Be 'RiskAccepted'
                $_.exceptionCreatedBy | Should -Be 'admin@partner.com'
            }
        }

        It 'deserialises only rows that pass the substring probe' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                New-CachedCveRow -CveId 'CVE-2024-0001' -Tenant 'contoso.onmicrosoft.com'
                foreach ($i in 1..20) { New-CachedCveRow -CveId "CVE-2024-9$i" -Tenant 'tailspin.onmicrosoft.com' }
            }

            # The mock does not pass through (pipeline binding inside mocks is unreliable);
            # it returns a fixed parsed row, which is only correct BECAUSE the probe means
            # the sole caller is the one matching row.
            $script:JsonParses = 0
            Mock -CommandName ConvertFrom-Json -MockWith {
                $script:JsonParses++
                [pscustomobject]@{ cveId = 'CVE-2024-0001'; customerId = 'contoso.onmicrosoft.com' }
            }

            $Response = Invoke-ExecAddCippCveException -Request (New-ExceptionRequest -ApplyTo 'AllAffected') -TriggerMetadata @{}

            $Response.Body.TenantsAffected | Should -Be 1
            # One parse for the single matching row. Anything near 21 means the probe is
            # gone and the whole cache is being deserialised again.
            $script:JsonParses | Should -Be 1
        }

        It 'deduplicates tenants when several cached rows match the CVE for the same tenant' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                New-CachedCveRow -CveId 'CVE-2024-0001' -Tenant 'contoso.onmicrosoft.com'
                New-CachedCveRow -CveId 'CVE-2024-0001' -Tenant 'contoso.onmicrosoft.com'
            }

            $Response = Invoke-ExecAddCippCveException -Request (New-ExceptionRequest -ApplyTo 'AllAffected') -TriggerMetadata @{}

            $Response.Body.TenantsAffected | Should -Be 1
            @($script:Written).Count | Should -Be 1
        }
    }

    Context 'other scopes' {
        It 'writes a single ALL row for Global' {
            $Response = Invoke-ExecAddCippCveException -Request (New-ExceptionRequest -ApplyTo 'Global') -TriggerMetadata @{}

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            @($script:Written).Count | Should -Be 1
            $script:Written[0].RowKey | Should -Be 'ALL'
            $script:Written[0].customerId | Should -Be 'ALL'
        }

        It 'scopes CurrentTenant to the tenant in the query' {
            $Response = Invoke-ExecAddCippCveException -Request (New-ExceptionRequest -ApplyTo 'CurrentTenant') -TriggerMetadata @{}

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            @($script:Written).Count | Should -Be 1
            $script:Written[0].RowKey | Should -Be 'contoso.onmicrosoft.com'
        }

        It 'rejects CurrentTenant when no single tenant is selected' {
            $Response = Invoke-ExecAddCippCveException -Request (New-ExceptionRequest -ApplyTo 'CurrentTenant' -TenantFilter 'AllTenants') -TriggerMetadata @{}

            $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
            @($script:Written).Count | Should -Be 0
        }
    }

    Context 'validation' {
        It 'returns BadRequest when required fields are missing' {
            $Request = New-ExceptionRequest
            $Request.Body.justification = ''

            $Response = Invoke-ExecAddCippCveException -Request $Request -TriggerMetadata @{}

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            @($script:Written).Count | Should -Be 0
        }
    }
}

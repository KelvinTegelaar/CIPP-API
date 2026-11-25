BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPDbItem { param($TenantFilter, $Type, $Partition, [switch]$CountsOnly) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    foreach ($Helper in 'Get-CippErrorStatusCode.ps1', 'Get-CippBulkStatusCode.ps1', 'Get-CIPPReportPage.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Helper -File | Select-Object -First 1 -ExpandProperty FullName)
    }

    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Defender'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $Folder 'Invoke-ListDefenderMachines.ps1') -Raw)))

    function New-Request ([hashtable]$Query) { [pscustomobject]@{ Query = [pscustomobject]$Query } }
    function New-Cache ([string]$Tenant, [int]$Rows) {
        $script:Cache[$Tenant] = @(
            [pscustomobject]@{ PartitionKey = $Tenant; RowKey = 'DefenderMachines-Count'; DataCount = $Rows; Timestamp = '2026-11-23T03:00:00Z' }
            for ($Index = 1; $Index -le $Rows; $Index++) {
                [pscustomobject]@{ PartitionKey = $Tenant; RowKey = "DefenderMachines-$Tenant-$Index"; Data = (@{ id = "$Tenant-$Index"; computerDnsName = "PC$Index" } | ConvertTo-Json -Compress); Timestamp = '2026-11-23T03:00:00Z' }
            }
        )
    }
}

Describe 'Invoke-ListDefenderMachines' {
    BeforeEach {
        $script:Cache = @{}
        Mock Write-LogMessage {}
        Mock Get-Tenants { 'a.com', 'b.com', 'c.com' | ForEach-Object { [pscustomobject]@{ defaultDomainName = $_ } } }
        Mock Get-CIPPDbItem -ParameterFilter { $CountsOnly } {
            foreach ($Tenant in $script:Cache.Keys) { $script:Cache[$Tenant].Where({ $_.RowKey -eq 'DefenderMachines-Count' }) }
        }
        Mock Get-CIPPDbItem -ParameterFilter { -not $CountsOnly } {
            $Key = $Partition ?? $TenantFilter
            if ($script:Cache.ContainsKey($Key)) { $script:Cache[$Key] }
        }
    }

    It 'requires a tenant' {
        (Invoke-ListDefenderMachines -Request (New-Request @{})).StatusCode | Should -Be 400
    }

    It 'returns a one element array with the cache timestamp and skips the count row' {
        New-Cache 'a.com' 1
        $Response = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com' })
        $Response.StatusCode | Should -Be 200
        $Response.Body | Should -HaveCount 1
        $Response.Body[0].id | Should -Be 'a.com-1'
        $Response.Body[0].CacheTimestamp | Should -Be '2026-11-23T03:00:00Z'
        Should -Invoke Get-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'a.com' -and -not $Partition -and $Type -eq 'DefenderMachines' }
    }

    It 'returns 404 when the tenant was never synced' {
        $Response = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com' })
        $Response.StatusCode | Should -Be 404
        $Response.Body.Results | Should -BeLike '*Sync the report data first*'
    }

    It 'returns 200 with no rows for a confirmed empty snapshot, paged or not' {
        New-Cache 'a.com' 0
        $Plain = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com' })
        $Plain.StatusCode | Should -Be 200
        @($Plain.Body) | Should -HaveCount 0
        $Paged = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com'; manualPagination = $true })
        $Paged.StatusCode | Should -Be 200
        @($Paged.Body.Results) | Should -HaveCount 0
    }

    It 'returns 500 when cached rows and the count marker are incomplete' {
        New-Cache 'a.com' 1
        $CountRow, $DeviceRow = $script:Cache['a.com']
        $script:Cache['a.com'] = @($CountRow)
        (Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com' })).StatusCode | Should -Be 500
        $script:Cache['a.com'] = @($DeviceRow)
        (Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com' })).StatusCode | Should -Be 500
    }

    It 'returns 500 when a row is invalid or storage fails' {
        New-Cache 'a.com' 1
        $script:Cache['a.com'][1].Data = '{}'
        (Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com' })).StatusCode | Should -Be 500
        $script:Cache['a.com'][1].Data = 'not json'
        (Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com' })).StatusCode | Should -Be 500
        Mock Get-CIPPDbItem -ParameterFilter { -not $CountsOnly } { throw 'storage unavailable' }
        (Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com' })).StatusCode | Should -Be 500
    }

    Context 'AllTenants without paging' {
        It 'stamps the tenant and skips tenants that were never synced' {
            New-Cache 'a.com' 2
            New-Cache 'c.com' 1
            $Response = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'AllTenants' })
            $Response.StatusCode | Should -Be 200
            $Response.Body.Tenant | Should -Be @('a.com', 'a.com', 'c.com')
            Should -Invoke Get-CIPPDbItem -Times 3 -Exactly -ParameterFilter { $Partition -and $Type -eq 'DefenderMachines' }
        }

        It 'returns 207 with the readable tenants when one tenant fails' {
            New-Cache 'a.com' 1
            New-Cache 'b.com' 1
            Mock Get-CIPPDbItem -ParameterFilter { $Partition -eq 'b.com' } { throw 'storage unavailable' }
            $Response = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'AllTenants' })
            $Response.StatusCode | Should -Be 207
            @($Response.Body.Tenant | Select-Object -Unique) | Should -Be @('a.com')
        }

        It 'returns 500 with a readable error when every attempted tenant fails' {
            New-Cache 'a.com' 1
            Mock Get-CIPPDbItem -ParameterFilter { $Partition } { throw 'storage unavailable' }
            $Response = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'AllTenants' })
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -BeLike 'Failed to read*'
        }
    }

    Context 'with paging' {
        BeforeEach {
            New-Cache 'a.com' 250
            New-Cache 'b.com' 250
            New-Cache 'c.com' 250
            New-Cache 'gone.com' 250
        }

        It 'forwards the page size and replays the continuation without gaps, repeats or out of scope tenants' {
            $Seen = [System.Collections.Generic.List[string]]::new()
            $Token = $null
            $Pages = 0
            do {
                $Query = @{ tenantFilter = 'AllTenants'; manualPagination = $true; PageSize = 250 }
                if ($Token) { $Query.nextLink = $Token }
                $Response = Invoke-ListDefenderMachines -Request (New-Request $Query)
                $Response.StatusCode | Should -Be 200
                $Seen.AddRange([string[]]@($Response.Body.Results.id))
                $Token = $Response.Body.Metadata.nextLink
                $Pages++
            } while ($Token -and $Pages -lt 10)
            $Pages | Should -Be 3
            $Seen.Count | Should -Be 750
            @($Seen | Select-Object -Unique) | Should -HaveCount 750
            $Seen.Where({ $_ -like 'gone.com-*' }) | Should -HaveCount 0
        }

        It 'returns 207 with the failed tenant count and keeps the continuation' {
            Mock Get-CIPPDbItem -ParameterFilter { $Partition -eq 'b.com' } { throw 'storage unavailable' }
            $Response = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'AllTenants'; manualPagination = $true; PageSize = 500 })
            $Response.StatusCode | Should -Be 207
            $Response.Body.Metadata.FailedTenants | Should -Be 1
            $Response.Body.Metadata.nextLink | Should -Be 'b.com'
            @($Response.Body.Results.Tenant | Select-Object -Unique) | Should -Be @('a.com')
        }

        It 'returns 500 when every attempted tenant fails' {
            Mock Get-CIPPDbItem -ParameterFilter { $Partition } { throw 'storage unavailable' }
            $Response = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'AllTenants'; manualPagination = $true; PageSize = 250 })
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -BeLike 'Failed to read*'
        }

        It 'serves a single tenant as one page' {
            $Response = Invoke-ListDefenderMachines -Request (New-Request @{ tenantFilter = 'a.com'; manualPagination = $true })
            $Response.StatusCode | Should -Be 200
            $Response.Body.Results | Should -HaveCount 250
            $Response.Body.Metadata.Keys | Should -Not -Contain 'nextLink'
        }
    }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPDefenderIndicator { param($TenantFilter, $PageSize) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, $Partition, [switch]$CountsOnly) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-NormalizedError { param($Message) $Message }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    foreach ($Helper in 'Get-CippErrorStatusCode.ps1', 'Get-CippBulkStatusCode.ps1', 'Get-CIPPReportPage.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Helper -File | Select-Object -First 1 -ExpandProperty FullName)
    }

    $script:EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Defender/Invoke-ListDefenderIndicators.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $script:EndpointPath -Raw)))

    function New-Request ([hashtable]$Query) { [pscustomobject]@{ Query = [pscustomobject]$Query; Headers = @{} } }
    function New-Cache ([string]$Tenant, [int]$Rows) {
        $script:Cache[$Tenant] = @(
            [pscustomobject]@{ PartitionKey = $Tenant; RowKey = 'DefenderIndicators-Count'; DataCount = $Rows; Timestamp = '2026-11-23T03:00:00Z' }
            for ($Index = 1; $Index -le $Rows; $Index++) {
                [pscustomobject]@{ PartitionKey = $Tenant; RowKey = "DefenderIndicators-$Tenant-$Index"; Data = (@{ id = "$Tenant-$Index"; indicatorValue = "bad$Index.example"; indicatorType = 'DomainName'; action = 'Block' } | ConvertTo-Json -Compress); Timestamp = '2026-11-23T03:00:00Z' }
            }
        )
    }
}

Describe 'Invoke-ListDefenderIndicators' {
    BeforeEach {
        $script:Cache = @{}
        Mock Write-LogMessage {}
        Mock Get-CIPPDefenderIndicator { @{ id = '11'; indicatorValue = 'bad.example'; indicatorType = 'DomainName'; action = 'Block' }; @{ id = '12'; indicatorValue = 'https://bad.example/x'; indicatorType = 'Url'; action = 'Warn' } }
        Mock Get-Tenants { 'a.com', 'b.com', 'c.com' | ForEach-Object { [pscustomobject]@{ defaultDomainName = $_ } } }
        Mock Get-CIPPDbItem -ParameterFilter { $CountsOnly } {
            foreach ($Tenant in $script:Cache.Keys) { $script:Cache[$Tenant].Where({ $_.RowKey -eq 'DefenderIndicators-Count' }) }
        }
        Mock Get-CIPPDbItem -ParameterFilter { -not $CountsOnly } {
            $Key = $Partition ?? $TenantFilter
            if ($script:Cache.ContainsKey($Key)) { $script:Cache[$Key] }
        }
    }

    It 'declares Security.Defender.Read and accepts tenant groups' {
        $Source = Get-Content -LiteralPath $script:EndpointPath -Raw
        $Source -match '\.FUNCTIONALITY\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Entrypoint,TenantGroup'
        $Source -match '\.ROLE\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Security.Defender.Read'
    }

    It 'requires a tenant' {
        (Invoke-ListDefenderIndicators -Request (New-Request @{})).StatusCode | Should -Be 400
        Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
    }

    Context 'one tenant, live' {
        It 'reads Defender live for that tenant and stamps the tenant on every row' {
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com' })
            $Response.StatusCode | Should -Be 200
            $Response.Body | Should -HaveCount 2
            $Response.Body.id | Should -Be @('11', '12')
            $Response.Body.Tenant | Should -Be @('a.com', 'a.com')
            Should -Invoke Get-CIPPDefenderIndicator -Times 1 -Exactly -ParameterFilter { $TenantFilter -ceq 'a.com' }
            Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
        }

        It 'returns a one element array for one indicator and an empty array for none' {
            Mock Get-CIPPDefenderIndicator { @{ id = '11'; indicatorValue = 'bad.example' } }
            $One = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com' })
            , $One.Body | Should -BeOfType [object[]]
            $One.Body | Should -HaveCount 1
            Mock Get-CIPPDefenderIndicator {}
            $None = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com' })
            $None.StatusCode | Should -Be 200
            @($None.Body) | Should -HaveCount 0
        }

        It 'returns 500 with the Defender message when the read fails' {
            Mock Get-CIPPDefenderIndicator { throw 'Forbidden' }
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com' })
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -BeLike '*Forbidden*'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $tenant -eq 'a.com' }
        }
    }

    Context 'one tenant, cached' {
        It 'reads the cache with the timestamp and skips the count row when manualPagination is <Paged>' -ForEach @(
            @{ Paged = $false }
            @{ Paged = $true }
        ) {
            New-Cache 'a.com' 1
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com'; UseReportDB = $true; manualPagination = $Paged })
            $Response.StatusCode | Should -Be 200
            $Rows = @(if ($Paged) { $Response.Body.Results } else { $Response.Body })
            $Rows | Should -HaveCount 1
            $Rows[0].id | Should -Be 'a.com-1'
            $Rows[0].Tenant | Should -Be 'a.com'
            $Rows[0].CacheTimestamp | Should -Be '2026-11-23T03:00:00Z'
            Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
        }

        It 'returns 404 when the tenant was never synced' {
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com'; UseReportDB = $true })
            $Response.StatusCode | Should -Be 404
            $Response.Body.Results | Should -BeLike '*Sync the report data first*'
        }

        It 'returns 200 with no rows for a confirmed empty snapshot, paged or not' {
            New-Cache 'a.com' 0
            $Plain = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com'; UseReportDB = $true })
            $Plain.StatusCode | Should -Be 200
            @($Plain.Body) | Should -HaveCount 0
            $Paged = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com'; UseReportDB = $true; manualPagination = $true })
            $Paged.StatusCode | Should -Be 200
            @($Paged.Body.Results) | Should -HaveCount 0
        }

        It 'returns 500 when the cached rows and the count marker disagree or a row is unreadable' {
            New-Cache 'a.com' 1
            $CountRow, $Row = $script:Cache['a.com']
            $script:Cache['a.com'] = @($CountRow)
            (Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com'; UseReportDB = $true })).StatusCode | Should -Be 500
            $script:Cache['a.com'] = @($Row)
            (Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com'; UseReportDB = $true })).StatusCode | Should -Be 500
            $Row.Data = 'not json'
            $script:Cache['a.com'] = @($CountRow, $Row)
            (Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com'; UseReportDB = $true })).StatusCode | Should -Be 500
        }

        It 'rejects a partially written snapshot even when some rows are readable' {
            New-Cache 'a.com' 1
            $script:Cache['a.com'][0].DataCount = 2
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'a.com'; UseReportDB = $true })
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -BeLike '*incomplete*'
        }
    }

    Context 'AllTenants without paging' {
        It 'reads the cache, stamps the tenant and skips tenants that were never synced' {
            New-Cache 'a.com' 2
            New-Cache 'c.com' 1
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'AllTenants' })
            $Response.StatusCode | Should -Be 200
            $Response.Body.Tenant | Should -Be @('a.com', 'a.com', 'c.com')
            Should -Invoke Get-CIPPDefenderIndicator -Times 0 -Exactly
            Should -Invoke Get-CIPPDbItem -Times 3 -Exactly -ParameterFilter { $Partition -and $Type -eq 'DefenderIndicators' }
        }

        It 'returns 207 with the readable tenants when one tenant fails' {
            New-Cache 'a.com' 1
            New-Cache 'b.com' 1
            Mock Get-CIPPDbItem -ParameterFilter { $Partition -eq 'b.com' } { throw 'storage unavailable' }
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'AllTenants' })
            $Response.StatusCode | Should -Be 207
            @($Response.Body.Tenant | Select-Object -Unique) | Should -Be @('a.com')
        }

        It 'returns 500 when every attempted tenant fails' {
            New-Cache 'a.com' 1
            Mock Get-CIPPDbItem -ParameterFilter { $Partition } { throw 'storage unavailable' }
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'AllTenants' })
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -BeLike 'Failed to read*'
        }
    }

    Context 'AllTenants with paging' {
        BeforeEach {
            New-Cache 'a.com' 250
            New-Cache 'b.com' 250
            New-Cache 'c.com' 250
            New-Cache 'gone.com' 250
        }

        It 'replays the continuation without gaps, repeats or out of scope tenants' {
            $Seen = [System.Collections.Generic.List[string]]::new()
            $Token = $null
            $Pages = 0
            do {
                $Query = @{ tenantFilter = 'AllTenants'; manualPagination = $true; PageSize = 250 }
                if ($Token) { $Query.nextLink = $Token }
                $Response = Invoke-ListDefenderIndicators -Request (New-Request $Query)
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

        It 'returns 207 with the failed tenant count' {
            Mock Get-CIPPDbItem -ParameterFilter { $Partition -eq 'b.com' } { throw 'storage unavailable' }
            $Response = Invoke-ListDefenderIndicators -Request (New-Request @{ tenantFilter = 'AllTenants'; manualPagination = $true; PageSize = 500 })
            $Response.StatusCode | Should -Be 207
            $Response.Body.Metadata.FailedTenants | Should -Be 1
            @($Response.Body.Results.Tenant | Select-Object -Unique) | Should -Be @('a.com')
        }

        It 'continues to the next tenant when every read on a page fails' {
            Mock Get-CIPPDbItem -ParameterFilter { $Partition -eq 'a.com' } { throw 'storage unavailable' }
            $Query = @{ tenantFilter = 'AllTenants'; manualPagination = $true; PageSize = 250 }
            $FailedPage = Invoke-ListDefenderIndicators -Request (New-Request $Query)
            $FailedPage.StatusCode | Should -Be 207
            $FailedPage.Body.Metadata.FailedTenants | Should -Be 1
            $Query.nextLink = $FailedPage.Body.Metadata.nextLink
            $Query.nextLink | Should -Be 'a.com'
            $NextPage = Invoke-ListDefenderIndicators -Request (New-Request $Query)
            $NextPage.StatusCode | Should -Be 200
            @($NextPage.Body.Results.Tenant | Select-Object -Unique) | Should -Be @('b.com')
        }
    }
}

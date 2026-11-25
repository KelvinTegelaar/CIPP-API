# Pester tests for Clear-CIPPDbCache and Remove-CIPPDbItem.

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }

    function Get-FakeTableList {
        param([string]$TableName)
        if ([string]::IsNullOrWhiteSpace($TableName)) { $TableName = 'CippReportingDB' }
        if (-not $script:FakeTables.ContainsKey($TableName)) {
            $script:FakeTables[$TableName] = [System.Collections.Generic.List[object]]::new()
        }
        $TableName
    }

    function Invoke-FakeTableFilter {
        param($Rows, [string]$Filter)
        $Result = @($Rows)
        if ($Filter -match "PartitionKey eq '([^']*)'") {
            $Pk = $Matches[1]
            $Result = @($Result | Where-Object { $_.PartitionKey -eq $Pk })
        }
        if ($Filter -match "RowKey eq '([^']*)'") {
            $Rk = $Matches[1]
            $Result = @($Result | Where-Object { $_.RowKey -eq $Rk })
        }
        if ($Filter -match "RowKey ge '([^']*)'") {
            $Ge = $Matches[1]
            # Table storage compares keys ordinally; -ge is culture-aware and sorts '|' below '0'
            $Result = @($Result | Where-Object { [string]::CompareOrdinal($_.RowKey, $Ge) -ge 0 })
        }
        if ($Filter -match "RowKey lt '([^']*)'") {
            $Lt = $Matches[1]
            $Result = @($Result | Where-Object { [string]::CompareOrdinal($_.RowKey, $Lt) -lt 0 })
        }
        if ($Filter -match "PartitionKey ne '([^']*)'") {
            $NotPk = $Matches[1]
            $Result = @($Result | Where-Object { $_.PartitionKey -ne $NotPk })
        }
        if ($Filter -match 'DataCount ge 0') {
            $Result = @($Result | Where-Object { $null -ne $_.DataCount })
        }
        $Result
    }

    function ConvertTo-FakeEntity {
        param($Entity)
        if ($Entity -is [hashtable]) { return [pscustomobject]$Entity }
        $Clone = [ordered]@{}
        foreach ($Property in $Entity.PSObject.Properties) { $Clone[$Property.Name] = $Property.Value }
        [pscustomobject]$Clone
    }

    function Get-CIPPAzDataTableEntity {
        param($TableName, $Context, $Filter, $Property, $First, [switch]$Count)
        $Name = Get-FakeTableList -TableName $(if ($TableName) { $TableName } else { 'CippReportingDB' })
        $Rows = $script:FakeTables[$Name]
        $Matched = @(Invoke-FakeTableFilter -Rows $Rows -Filter $Filter | ForEach-Object { ConvertTo-FakeEntity -Entity $_ })
        if ($First -and $Matched.Count -gt $First) {
            $Matched = $Matched[0..($First - 1)]
        }
        $Matched
    }

    function Add-CIPPAzDataTableEntity {
        [CmdletBinding()]
        param($TableName, $Context, $Entity, [switch]$Force, [switch]$CreateTableIfNotExists)
        $Name = Get-FakeTableList -TableName $(if ($TableName) { $TableName } else { 'CippReportingDB' })
        $Rows = $script:FakeTables[$Name]
        foreach ($Item in @($Entity)) {
            if ($null -eq $Item) { continue }
            $New = ConvertTo-FakeEntity -Entity $Item
            $Existing = $null
            for ($i = 0; $i -lt $Rows.Count; $i++) {
                if ($Rows[$i].PartitionKey -eq $New.PartitionKey -and $Rows[$i].RowKey -eq $New.RowKey) {
                    $Existing = $Rows[$i]
                    break
                }
            }
            if ($Existing) {
                if (-not $Force) { continue }
                [void]$Rows.Remove($Existing)
            }
            [void]$Rows.Add($New)
        }
    }

    function Remove-CIPPAzDataTableEntity {
        param($TableName, $Context, $Entity, [switch]$Force)
        $Name = Get-FakeTableList -TableName $(if ($TableName) { $TableName } else { 'CippReportingDB' })
        $Rows = $script:FakeTables[$Name]
        foreach ($Item in @($Entity)) {
            if ($null -eq $Item) { continue }
            $Existing = $null
            for ($i = 0; $i -lt $Rows.Count; $i++) {
                if ($Rows[$i].PartitionKey -eq $Item.PartitionKey -and $Rows[$i].RowKey -eq $Item.RowKey) {
                    $Existing = $Rows[$i]
                    break
                }
            }
            if ($Existing) { [void]$Rows.Remove($Existing) }
        }
    }

    function Get-AzDataTableEntity {
        param($TableName, $Context, $Filter, $Property, $First, [switch]$Count)
        Get-CIPPAzDataTableEntity @PSBoundParameters
    }

    function Remove-AzDataTableEntity {
        param($TableName, $Context, $Entity, [switch]$Force)
        Remove-CIPPAzDataTableEntity @PSBoundParameters
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-Tenants {
        param($TenantFilter, [switch]$IncludeErrors)
        if (-not $TenantFilter) {
            return @(
                [pscustomobject]@{ customerId = 'tenant-guid-1'; defaultDomainName = 'contoso.com' }
                [pscustomobject]@{ customerId = 'tenant-guid-2'; defaultDomainName = 'fabrikam.com' }
            )
        }
        switch -Regex ($TenantFilter) {
            '^(contoso\.com|contoso\.onmicrosoft\.com)$' {
                return [pscustomobject]@{ customerId = 'tenant-guid-1'; defaultDomainName = 'contoso.com' }
            }
            '^(fabrikam\.com)$' {
                return [pscustomobject]@{ customerId = 'tenant-guid-2'; defaultDomainName = 'fabrikam.com' }
            }
            default { return $null }
        }
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDbItem.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Remove-CIPPDbItem.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Clear-CIPPDbCache.ps1')
}

Describe 'Remove-CIPPDbItem' {
    BeforeEach {
        $script:FakeTables = @{}
        Add-CIPPAzDataTableEntity -TableName 'CippReportingDB' -Entity @(
            @{ PartitionKey = 'contoso.com'; RowKey = 'Users-user-1'; Data = '{"id":"user-1"}'; Type = 'Users'; ETag = 'etag-1' }
            @{ PartitionKey = 'contoso.com'; RowKey = 'Users-Count'; DataCount = 2; ETag = 'etag-c' }
        ) -Force
    }

    It 'removes by RowKey and decrements DataCount' {
        Remove-CIPPDbItem -TenantFilter 'contoso.com' -Type 'Users' -RowKey 'Users-user-1' -ETag 'etag-1'

        $Remaining = @($script:FakeTables['CippReportingDB'])
        ($Remaining | Where-Object { $_.RowKey -eq 'Users-user-1' }).Count | Should -Be 0
        ($Remaining | Where-Object { $_.RowKey -eq 'Users-Count' }).DataCount | Should -Be 1
        $Copy = $Remaining | Where-Object { $_.PartitionKey -eq 'CippCounts' -and $_.RowKey -eq 'Users|contoso.com' }
        $Copy.DataCount | Should -Be 1
        $Copy.Tenant | Should -Be 'contoso.com'
    }

    It 'removes by ItemId and decrements DataCount' {
        Remove-CIPPDbItem -TenantFilter 'contoso.com' -Type 'Users' -ItemId 'user-1'

        $Remaining = @($script:FakeTables['CippReportingDB'])
        ($Remaining | Where-Object { $_.RowKey -eq 'Users-user-1' }).Count | Should -Be 0
        ($Remaining | Where-Object { $_.RowKey -eq 'Users-Count' }).DataCount | Should -Be 1
    }

    It 'rejects RowKey that does not match Type' {
        { Remove-CIPPDbItem -TenantFilter 'contoso.com' -Type 'Users' -RowKey 'Groups-g1' } | Should -Throw '*does not match type*'
    }
}

Describe 'Clear-CIPPDbCache' {
    BeforeEach {
        $script:FakeTables = @{}
        Add-CIPPAzDataTableEntity -TableName 'CippReportingDB' -Entity @(
            @{ PartitionKey = 'contoso.com'; RowKey = 'Users-user-1'; Data = '{"id":"user-1"}'; Type = 'Users' }
            @{ PartitionKey = 'contoso.com'; RowKey = 'Users-user-2'; Data = '{"id":"user-2"}'; Type = 'Users' }
            @{ PartitionKey = 'contoso.com'; RowKey = 'Users-Count'; DataCount = 2 }
            @{ PartitionKey = 'contoso.com'; RowKey = 'Groups-g1'; Data = '{"id":"g1"}'; Type = 'Groups' }
            @{ PartitionKey = 'contoso.com'; RowKey = 'Groups-Count'; DataCount = 1 }
            @{ PartitionKey = 'fabrikam.com'; RowKey = 'Users-user-a'; Data = '{"id":"user-a"}'; Type = 'Users' }
            @{ PartitionKey = 'fabrikam.com'; RowKey = 'Users-Count'; DataCount = 1 }
        ) -Force
    }

    It 'empties one tenant type and resets Count to 0' {
        $Result = Clear-CIPPDbCache -TenantFilter 'contoso.com' -Type 'Users'

        # Data rows only (Count is upserted to 0, not counted as a delete).
        $Result.RemovedCount | Should -Be 2
        $Result.Tenant | Should -Be 'contoso.com'
        $Result.Type | Should -Be 'Users'

        $Remaining = @($script:FakeTables['CippReportingDB'])
        ($Remaining | Where-Object { $_.PartitionKey -eq 'contoso.com' -and $_.RowKey -like 'Users-user*' }).Count | Should -Be 0
        ($Remaining | Where-Object { $_.PartitionKey -eq 'contoso.com' -and $_.RowKey -eq 'Users-Count' }).DataCount | Should -Be 0
        ($Remaining | Where-Object { $_.RowKey -eq 'Groups-g1' }).Count | Should -Be 1
        ($Remaining | Where-Object { $_.PartitionKey -eq 'fabrikam.com' -and $_.RowKey -eq 'Users-user-a' }).Count | Should -Be 1
    }

    It 'empties a type across AllTenants partitions' {
        $Result = Clear-CIPPDbCache -TenantFilter 'AllTenants' -Type 'Users'

        $Result.RemovedCount | Should -Be 3
        $Result.Tenant | Should -Be 'AllTenants'

        $Remaining = @($script:FakeTables['CippReportingDB'])
        ($Remaining | Where-Object { $_.RowKey -like 'Users-user*' }).Count | Should -Be 0
        ($Remaining | Where-Object { $_.RowKey -eq 'Users-Count' -and $_.DataCount -eq 0 }).Count | Should -Be 2
        ($Remaining | Where-Object { $_.RowKey -eq 'Groups-g1' }).Count | Should -Be 1
        @($Remaining | Where-Object { $_.PartitionKey -eq 'CippCounts' -and $_.DataCount -eq 0 }).RowKey | Sort-Object | Should -Be @('Users|contoso.com', 'Users|fabrikam.com')
    }

    It 'keeps CippCounts out of an AllTenants countsOnly scan' {
        Clear-CIPPDbCache -TenantFilter 'AllTenants' -Type 'Users' | Out-Null
        $Rows = @(Get-CIPPDbItem -TenantFilter 'allTenants' -CountsOnly)
        $Rows.Count | Should -BeGreaterThan 0
        $Rows.PartitionKey | Should -Not -Contain 'CippCounts'
    }

    It 'returns RemovedCount 0 when nothing matches' {
        $Result = Clear-CIPPDbCache -TenantFilter 'contoso.com' -Type 'Devices'
        $Result.RemovedCount | Should -Be 0
        $Remaining = @($script:FakeTables['CippReportingDB'])
        ($Remaining | Where-Object { $_.RowKey -eq 'Devices-Count' }).DataCount | Should -Be 0
    }
}

Describe 'Get-CIPPDbItem -CountsOnly for AllTenants' {
    BeforeEach {
        $script:FakeTables = @{}
        Add-CIPPAzDataTableEntity -TableName 'CippReportingDB' -Entity @(
            @{ PartitionKey = 'contoso.com'; RowKey = 'Users-u1'; Data = '{}' }
            @{ PartitionKey = 'contoso.com'; RowKey = 'Users-Count'; DataCount = 5; Type = 'Users' }
            @{ PartitionKey = 'contoso.com'; RowKey = 'Groups-Count'; DataCount = 2; Type = 'Groups' }
            @{ PartitionKey = 'fabrikam.com'; RowKey = 'Users-Count'; DataCount = 9; Type = 'Users' }
            @{ PartitionKey = 'CippCounts'; RowKey = 'Users|contoso.com'; Tenant = 'contoso.com'; Type = 'Users'; DataCount = 5 }
            @{ PartitionKey = 'CippCounts'; RowKey = 'Groups|contoso.com'; Tenant = 'contoso.com'; Type = 'Groups'; DataCount = 2 }
        ) -Force
    }

    It 'reads the CippCounts copies in the count rows own shape and falls back for tenants without copies' {
        $Rows = @(Get-CIPPDbItem -TenantFilter 'allTenants' -CountsOnly)

        @($Rows | ForEach-Object { '{0}/{1}={2}' -f $_.PartitionKey, $_.RowKey, $_.DataCount } | Sort-Object) |
            Should -Be @('contoso.com/Groups-Count=2', 'contoso.com/Users-Count=5', 'fabrikam.com/Users-Count=9')
    }

    It 'reads one type as a key range and falls back per tenant' {
        $Rows = @(Get-CIPPDbItem -TenantFilter 'AllTenants' -CountsOnly -Type 'Users')

        @($Rows | ForEach-Object { '{0}={1}' -f $_.PartitionKey, $_.DataCount } | Sort-Object) | Should -Be @('contoso.com=5', 'fabrikam.com=9')
    }

    It 'leaves a single-tenant read on the tenant partition' {
        $Rows = @(Get-CIPPDbItem -TenantFilter 'contoso.com' -CountsOnly)

        @($Rows.PartitionKey | Sort-Object -Unique) | Should -Be @('contoso.com')
        $Rows.Count | Should -Be 2
    }
}

# Pester tests for Clear-CIPPDbCache and Remove-CIPPDbItem.

BeforeAll {
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
            $Result = @($Result | Where-Object { $_.RowKey -ge $Ge })
        }
        if ($Filter -match "RowKey lt '([^']*)'") {
            $Lt = $Matches[1]
            $Result = @($Result | Where-Object { $_.RowKey -lt $Lt })
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
    }

    It 'returns RemovedCount 0 when nothing matches' {
        $Result = Clear-CIPPDbCache -TenantFilter 'contoso.com' -Type 'Devices'
        $Result.RemovedCount | Should -Be 0
        $Remaining = @($script:FakeTables['CippReportingDB'])
        ($Remaining | Where-Object { $_.RowKey -eq 'Devices-Count' }).DataCount | Should -Be 0
    }
}

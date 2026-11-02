# Pester tests for Repair-CIPPTable and TableNotFound self-heal in the entity wrappers.
#
# A stale CIPPEnsuredTables entry (migration / external drop without Unregister) causes
# entity ops to 404. These tests protect: repair recreates + re-caches, wrappers retry
# once, non-404 errors are not repaired, and a failed create is not remembered as done.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $GraphHelper = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GraphHelper'

    $script:CreateCalls = [System.Collections.Generic.List[string]]::new()
    $script:GetCalls = 0
    $script:AddCalls = 0
    $script:RemoveCalls = 0
    $script:FailGetWithNotFound = $false
    $script:FailGetWithOther = $false
    $script:FailAddWithNotFound = $false
    $script:FailAddWithOther = $false
    $script:FailRemoveWithNotFound = $false
    $script:FailRemoveWithOther = $false
    $script:CreateShouldConflict = $false
    $script:CreateShouldFail = $false

    function New-AzDataTableContext {
        param($ConnectionString, $TableName, $MaxConnectionsPerServer)
        [pscustomobject]@{ TableName = $TableName; ConnectionString = $ConnectionString }
    }

    function New-AzDataTable {
        param($Context)
        if ($script:CreateShouldFail) {
            throw 'storage unavailable'
        }
        if ($script:CreateShouldConflict) {
            $script:CreateCalls.Add($Context.TableName)
            $Ex = [System.Exception]::new('The table already exists. ErrorCode: TableAlreadyExists')
            throw $Ex
        }
        $script:CreateCalls.Add($Context.TableName)
    }

    function Get-AzDataTableLargeEntity {
        [CmdletBinding()]
        param(
            $Context,
            $Filter,
            $Property,
            $First,
            $Skip,
            $Sort,
            [switch]$Count,
            [int]$MaxRetries
        )
        $script:GetCalls++
        if ($script:FailGetWithNotFound) {
            $script:FailGetWithNotFound = $false
            $Ex = [System.Exception]::new("The table specified does not exist.`nErrorCode: TableNotFound")
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    $Ex, 'TableNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Context))
            return
        }
        if ($script:FailGetWithOther) {
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('throttled'), 'TooManyRequests', [System.Management.Automation.ErrorCategory]::OperationTimeout, $Context))
            return
        }
        [pscustomobject]@{ PartitionKey = 'Search'; RowKey = '1' }
    }

    function Add-AzDataTableLargeEntity {
        param(
            $Context,
            $Entity,
            [switch]$CreateTableIfNotExists,
            [switch]$Force,
            [string]$OperationType
        )
        $script:AddCalls++
        if ($script:FailAddWithNotFound) {
            $script:FailAddWithNotFound = $false
            throw [System.Exception]::new("The table specified does not exist.`nErrorCode: TableNotFound")
        }
        if ($script:FailAddWithOther) {
            throw [System.Exception]::new('EntityAlreadyExists')
        }
    }

    function Remove-AzDataTableLargeEntity {
        param(
            $Context,
            $Entity,
            [switch]$Force,
            [int]$MaxRetries
        )
        $script:RemoveCalls++
        if ($script:FailRemoveWithNotFound) {
            $script:FailRemoveWithNotFound = $false
            throw [System.Exception]::new("The table specified does not exist.`nErrorCode: TableNotFound")
        }
        if ($script:FailRemoveWithOther) {
            throw [System.Exception]::new('precondition failed')
        }
    }

    . (Join-Path $GraphHelper 'Unregister-CIPPTable.ps1')
    . (Join-Path $GraphHelper 'Test-CIPPTableNotFound.ps1')
    . (Join-Path $GraphHelper 'Repair-CIPPTable.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPAzDatatableEntity.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Add-CIPPAzDataTableEntity.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Remove-CIPPAzDataTableEntity.ps1')

    function Set-StorageAccount {
        param([string]$Name)
        $env:AzureWebJobsStorage = "DefaultEndpointsProtocol=https;AccountName=$Name;AccountKey=Zm9v;EndpointSuffix=core.windows.net"
    }

    function Reset-TableState {
        $script:CIPPEnsuredTables = [HashTable]::Synchronized(@{})
        $script:CIPPRepairingTable = $false
        $script:CreateCalls.Clear()
        $script:GetCalls = 0
        $script:AddCalls = 0
        $script:RemoveCalls = 0
        $script:FailGetWithNotFound = $false
        $script:FailGetWithOther = $false
        $script:FailAddWithNotFound = $false
        $script:FailAddWithOther = $false
        $script:FailRemoveWithNotFound = $false
        $script:FailRemoveWithOther = $false
        $script:CreateShouldConflict = $false
        $script:CreateShouldFail = $false
        Set-StorageAccount 'acctone'
    }

    function Get-CacheKey {
        param([string]$TableName)
        'acctone/{0}' -f $TableName
    }
}

Describe 'Test-CIPPTableNotFound' {
    It 'matches ErrorCode TableNotFound in the message' {
        $Ex = [System.Exception]::new('ErrorCode: TableNotFound')
        Test-CIPPTableNotFound $Ex | Should -BeTrue
    }

    It 'matches the table service not-found text' {
        $Ex = [System.Exception]::new('The table specified does not exist.')
        Test-CIPPTableNotFound $Ex | Should -BeTrue
    }

    It 'does not match unrelated errors' {
        $Ex = [System.Exception]::new('Entity already exists')
        Test-CIPPTableNotFound $Ex | Should -BeFalse
    }
}

Describe 'Repair-CIPPTable' {
    BeforeEach {
        Reset-TableState
    }

    It 'unregisters, creates, and marks the table ensured' {
        $script:CIPPEnsuredTables[(Get-CacheKey 'AuditLogSearches')] = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'

        Repair-CIPPTable -Context $Context

        $script:CreateCalls | Should -Be @('AuditLogSearches')
        $script:CIPPEnsuredTables.ContainsKey((Get-CacheKey 'AuditLogSearches')) | Should -BeTrue
    }

    It 'treats a concurrent create 409 as success and still caches the table' {
        $script:CreateShouldConflict = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'

        { Repair-CIPPTable -Context $Context } | Should -Not -Throw
        $script:CreateCalls | Should -Be @('AuditLogSearches')
        $script:CIPPEnsuredTables.ContainsKey((Get-CacheKey 'AuditLogSearches')) | Should -BeTrue
    }

    It 'does not cache a failed creation' {
        $script:CreateShouldFail = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'

        { Repair-CIPPTable -Context $Context } | Should -Throw
        $script:CIPPEnsuredTables.ContainsKey((Get-CacheKey 'AuditLogSearches')) | Should -BeFalse
    }

    It 'accepts -TableName and builds a context' {
        Repair-CIPPTable -TableName 'CippQueue'
        $script:CreateCalls | Should -Be @('CippQueue')
        $script:CIPPEnsuredTables.ContainsKey((Get-CacheKey 'CippQueue')) | Should -BeTrue
    }
}

Describe 'Get-CIPPAzDataTableEntity TableNotFound self-heal' {
    BeforeEach {
        Reset-TableState
        # Stale cache: table is "ensured" but storage no longer has it.
        $script:CIPPEnsuredTables[(Get-CacheKey 'AuditLogSearches')] = $true
    }

    It 'repairs and retries once on TableNotFound' {
        $script:FailGetWithNotFound = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'

        $Result = Get-CIPPAzDataTableEntity -Context $Context

        $script:GetCalls | Should -Be 2
        $script:CreateCalls | Should -Be @('AuditLogSearches')
        $Result.RowKey | Should -Be '1'
    }

    It 'does not repair non-TableNotFound errors' {
        $script:FailGetWithOther = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'
        $null = Get-CIPPAzDataTableEntity -Context $Context -ErrorAction SilentlyContinue

        $script:GetCalls | Should -Be 1
        $script:CreateCalls | Should -HaveCount 0
    }
}

Describe 'Add-CIPPAzDataTableEntity TableNotFound self-heal' {
    BeforeEach {
        Reset-TableState
        $script:CIPPEnsuredTables[(Get-CacheKey 'AuditLogSearches')] = $true
    }

    It 'repairs and retries once on TableNotFound' {
        $script:FailAddWithNotFound = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'
        $Entity = @{ PartitionKey = 'Search'; RowKey = '1'; Tenant = 'contoso.com' }

        { Add-CIPPAzDataTableEntity -Context $Context -Entity $Entity -Force } | Should -Not -Throw

        $script:AddCalls | Should -Be 2
        $script:CreateCalls | Should -Be @('AuditLogSearches')
    }

    It 'does not repair non-TableNotFound errors' {
        $script:FailAddWithOther = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'
        $Entity = @{ PartitionKey = 'Search'; RowKey = '1'; Tenant = 'contoso.com' }

        { Add-CIPPAzDataTableEntity -Context $Context -Entity $Entity -Force } | Should -Throw
        $script:AddCalls | Should -Be 1
        $script:CreateCalls | Should -HaveCount 0
    }
}

Describe 'Remove-CIPPAzDataTableEntity TableNotFound self-heal' {
    BeforeEach {
        Reset-TableState
        $script:CIPPEnsuredTables[(Get-CacheKey 'AuditLogSearches')] = $true
    }

    It 'repairs and retries once on TableNotFound' {
        $script:FailRemoveWithNotFound = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'
        $Entity = @{ PartitionKey = 'Search'; RowKey = '1'; ETag = '*' }

        { Remove-CIPPAzDataTableEntity -Context $Context -Entity $Entity -Force } | Should -Not -Throw

        $script:RemoveCalls | Should -Be 2
        $script:CreateCalls | Should -Be @('AuditLogSearches')
    }

    It 'does not repair non-TableNotFound errors' {
        $script:FailRemoveWithOther = $true
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName 'AuditLogSearches'
        $Entity = @{ PartitionKey = 'Search'; RowKey = '1'; ETag = '*' }

        { Remove-CIPPAzDataTableEntity -Context $Context -Entity $Entity -Force } | Should -Throw
        $script:RemoveCalls | Should -Be 1
        $script:CreateCalls | Should -HaveCount 0
    }
}

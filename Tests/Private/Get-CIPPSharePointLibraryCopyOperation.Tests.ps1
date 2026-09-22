# Pester tests for SharePointLibraryCopy operation store helpers

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharePointLibraryCopyOperation.ps1'
    $SetPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPSharePointLibraryCopyOperation.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }
    if (-not (Test-Path $SetPath)) { throw "Could not locate $SetPath" }

    function Get-CIPPTable {
        param($TableName)
        @{ Context = [pscustomobject]@{ TableName = $TableName } }
    }

    $script:TableRows = @()

    function Get-CIPPAzDataTableEntity {
        param($Context, $Filter)
        if ($Filter -match "PartitionKey eq '([^']+)' and RowKey eq '([^']+)'") {
            $tenant = $Matches[1]
            $rowKey = $Matches[2]
            return @($script:TableRows | Where-Object { $_.PartitionKey -eq $tenant -and $_.RowKey -eq $rowKey })
        }
        if ($Filter -match "PartitionKey eq '([^']+)' and startswith\(RowKey, '([^']+)'\)") {
            $tenant = $Matches[1]
            $prefix = $Matches[2]
            return @($script:TableRows | Where-Object { $_.PartitionKey -eq $tenant -and $_.RowKey.StartsWith($prefix) })
        }
        if ($Filter -match "PartitionKey eq '([^']+)'$") {
            $tenant = $Matches[1]
            return @($script:TableRows | Where-Object { $_.PartitionKey -eq $tenant })
        }
        return @()
    }

    function Remove-CIPPAzDataTableEntity {
        param($Context, $Entity, [switch]$Force)
        foreach ($Row in @($Entity)) {
            $script:TableRows = @($script:TableRows | Where-Object {
                    -not ($_.PartitionKey -eq $Row.PartitionKey -and $_.RowKey -eq $Row.RowKey)
                })
        }
    }

    function Add-CIPPAzDataTableEntity {
        param($Context, $Entity, [switch]$Force, [string]$OperationType = 'Add')
        foreach ($Row in @($Entity)) {
            $Existing = $script:TableRows | Where-Object {
                $_.PartitionKey -eq $Row.PartitionKey -and $_.RowKey -eq $Row.RowKey
            } | Select-Object -First 1
            if ($Existing -and $OperationType -eq 'UpsertMerge') {
                foreach ($Key in $Row.Keys) {
                    $Existing.$Key = $Row[$Key]
                }
            } elseif ($Existing -and $Force) {
                $script:TableRows = @($script:TableRows | Where-Object {
                        -not ($_.PartitionKey -eq $Row.PartitionKey -and $_.RowKey -eq $Row.RowKey)
                    })
                $script:TableRows += [pscustomobject]$Row
            } else {
                $script:TableRows += [pscustomobject]$Row
            }
        }
    }

    . $FunctionPath
    . $SetPath
}

Describe 'Get-CIPPSharePointLibraryCopyOperation' {
    BeforeEach {
        $script:TableRows = @()
    }

    It 'loads the primary row by exact RowKey' {
        $OpId = [guid]::NewGuid().Guid
        $script:TableRows = @(
            [pscustomobject]@{
                PartitionKey    = 'contoso.com'
                RowKey          = $OpId
                JobHandleCount  = 2
                CopyJobInfos    = '[{"JobId":"a"}]'
                HandleStates    = '[]'
                Status          = 'Processing'
            }
        )

        $Result = Get-CIPPSharePointLibraryCopyOperation -TenantFilter 'contoso.com' -OperationId $OpId

        $Result.OperationId | Should -Be $OpId
        $Result.CopyJobInfos.Count | Should -Be 1
    }

    It 'merges status updates without deleting CopyJobInfos' {
        $OpId = [guid]::NewGuid().Guid
        $script:TableRows = @(
            [pscustomobject]@{
                PartitionKey   = 'contoso.com'
                RowKey         = $OpId
                JobHandleCount = 1
                CopyJobInfos   = '[{"JobId":"a"}]'
                HandleStates   = '[]'
                Status         = 'Processing'
            }
        )

        Set-CIPPSharePointLibraryCopyOperation -TenantFilter 'contoso.com' -OperationId $OpId -Entity @{
            Status       = 'Completed'
            HandleStates = '[{"Status":"Success","IsComplete":true}]'
        }

        $Result = Get-CIPPSharePointLibraryCopyOperation -TenantFilter 'contoso.com' -OperationId $OpId
        $Result.Status | Should -Be 'Completed'
        $Result.CopyJobInfos.Count | Should -Be 1
        ($script:TableRows | Measure-Object).Count | Should -Be 1
    }
}

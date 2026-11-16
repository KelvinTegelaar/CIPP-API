BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Start-TableCleanup.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function New-AzDataTableContext { param($ConnectionString) }
    function Get-AzDataTable { param($Context) }
    function Start-CIPPOrchestrator { param($InputObject) }

    . $FunctionPath
}

Describe 'Start-TableCleanup Graph request cache tables' {
    BeforeEach {
        Mock New-AzDataTableContext {}
        Mock Get-AzDataTable { @('cacheusers', 'cacheauditLogssignInsfilteripAddresseq1', 'CacheCapabilities', 'cachelicenses', 'cacheQuarantineMessages', 'CippLogs') }
        Mock Start-CIPPOrchestrator {}
    }

    It 'adds a 24 hour, keys-only, 1000-row rule for each Graph cache table and none for fixed cache tables' {
        Start-TableCleanup
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter {
            $Rules = @($InputObject.Batch | Where-Object { $_.RawDelete })
            $Cutoff = (Get-Date).AddHours(-24).ToUniversalTime().ToString('yyyy-MM-ddTHH')
            $Rules.Count -eq 2 -and
            ($Rules.TableName -join ',') -eq 'cacheusers,cacheauditLogssignInsfilteripAddresseq1' -and
            @($Rules | Where-Object { $_.DataTableProps.First -eq 1000 -and $_.DataTableProps.Filter -like "Timestamp lt datetime'$Cutoff*" -and -not ($_.DataTableProps.Property -contains 'Data') }).Count -eq 2 -and
            @($InputObject.Batch | Where-Object { $_.TableName -eq 'cacheQuarantineMessages' }).Count -eq 1
        }
    }

    It 'still queues the other cleanup rules when listing tables fails' {
        Mock Get-AzDataTable { throw 'boom' }
        Start-TableCleanup 3>$null
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter {
            @($InputObject.Batch | Where-Object { $_.RawDelete }).Count -eq 0 -and @($InputObject.Batch | Where-Object { $_.TableName -eq 'CippReportingDB' }).Count -eq 1
        }
    }
}

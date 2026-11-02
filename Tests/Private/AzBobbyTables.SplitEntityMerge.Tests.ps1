# Pins how the vendored AzBobbyTables reassembles a split entity whose property is on more than one row.
#
# Rows split by the old PowerShell writer keep small properties such as TaskState on a later part row,
# and plain Update-AzDataTableEntity merges write only the root row. Concatenating the two copies read a
# completed task as 'CompletedPlanned', and the stale part row kept the scheduler re-running it every cycle.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Import-Module (Join-Path $BackendRoot 'Modules/AzBobbyTables') -ErrorAction Stop
    Get-AzDataTableSupportedEntityType | Out-Null

    # AzBobbyTables.Core and Azure.Data.Tables live in the module's private AssemblyLoadContext.
    $Core = @(foreach ($Context in [System.Runtime.Loader.AssemblyLoadContext]::All) {
            foreach ($Assembly in $Context.Assemblies) {
                if ($Assembly.GetName().Name -eq 'AzBobbyTables.Core') { $Assembly }
            }
        })[0]
    $Context = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($Core)
    $script:EntityType = $Context.LoadFromAssemblyName([System.Reflection.AssemblyName]::new('Azure.Data.Tables')).GetType('Azure.Data.Tables.TableEntity')
    $script:Splitter = $Core.GetType('PipeHow.AzBobbyTables.Core.EntitySplitter')

    function Merge-SplitRow {
        param([hashtable[]]$Rows)
        $Entities = [Array]::CreateInstance($script:EntityType, $Rows.Count)
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $Entity = [Activator]::CreateInstance($script:EntityType, @($Rows[$i].PartitionKey, $Rows[$i].RowKey))
            foreach ($Key in $Rows[$i].Keys.Where({ $_ -notin 'PartitionKey', 'RowKey' })) { $Entity[$Key] = $Rows[$i][$Key] }
            $Entities[$i] = $Entity
        }
        # A TableEntity is a dictionary, so it is returned inside a list or the pipeline enumerates its pairs.
        $Merged = [System.Collections.Generic.List[object]]::new()
        foreach ($Entity in $script:Splitter.GetMethod('Reassemble').Invoke($null, @($Entities, $null, $null))) { $Merged.Add($Entity) }
        , $Merged
    }
}

Describe 'Vendored AzBobbyTables split entity merge' {
    It 'returns the root row value of a property a split-unaware update duplicated' {
        $Merged = Merge-SplitRow @(
            @{ PartitionKey = 'ScheduledTask'; RowKey = 'task'; OriginalEntityId = 'task'; PartIndex = 0; TaskState = 'Completed'; ExecutedTime = 2 }
            @{ PartitionKey = 'ScheduledTask'; RowKey = 'task-part1'; OriginalEntityId = 'task'; PartIndex = 1; TaskState = 'Planned'; ExecutedTime = 1; CustomSubject = 'kept' }
        )

        $Merged.Count | Should -Be 1
        $Merged[0].RowKey | Should -Be 'task'
        $Merged[0]['TaskState'] | Should -Be 'Completed'
        $Merged[0]['ExecutedTime'] | Should -Be 2
        $Merged[0]['CustomSubject'] | Should -Be 'kept'
    }
}

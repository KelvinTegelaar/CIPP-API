function Update-CIPPAzDataTableEntity {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Updates entities that already exist in an Azure Table, without creating missing ones.
    .DESCRIPTION
    Thin wrapper around Update-AzDataTableEntity (AzBobbyTables), which merges into or
    replaces existing entities and fails for entities that do not exist. Use it instead
    of Add-CIPPAzDataTableEntity's UpsertMerge when recreating a concurrently deleted
    row would corrupt the table (e.g. flag stamps on rows another worker may be deleting).

    Not split-aware: this writes to the physical row only. Merging small scalar
    properties is safe even on a split entity (scalars live on the base row, which keeps
    the logical RowKey), but rewriting a property that may have been chunked for size
    must go through Update-AzDataTableLargeEntity or Add-CIPPAzDataTableEntity, or the
    stale chunks survive and corrupt reassembly on read.

    Kept in the style of the other CIPP table helpers: defaults MaxRetries to 3 for
    throttled requests and strips null-valued properties, which the table service cannot
    store and the binary module rejects.
    #>
    [CmdletBinding()]
    param(
        $Context,
        $Entity,
        [ValidateSet('UpdateMerge', 'UpdateReplace')]
        [string]$OperationType = 'UpdateMerge',
        [switch]$Force,
        [int]$MaxRetries = 3
    )

    if ($null -eq $Context) {
        throw 'Context parameter cannot be null'
    }

    if ($null -eq $Entity) {
        Write-Warning 'Entity parameter is null - nothing to process'
        return
    }

    $Entities = [System.Collections.Generic.List[object]]::new()
    foreach ($SingleEnt in @($Entity)) {
        if ($null -eq $SingleEnt) {
            Write-Warning 'Skipping null entity'
            continue
        }

        # Remove null-valued properties before handing the entity to the binary module
        if ($SingleEnt -is [hashtable]) {
            if ($SingleEnt.Count -eq 0) {
                Write-Warning 'Skipping empty hashtable entity'
                continue
            }
            foreach ($key in @($SingleEnt.Keys)) {
                if ($null -eq $SingleEnt[$key]) {
                    $SingleEnt.Remove($key)
                }
            }
        } elseif ($SingleEnt -is [PSCustomObject]) {
            if (($SingleEnt.PSObject.Properties | Measure-Object).Count -eq 0) {
                Write-Warning 'Skipping empty PSCustomObject entity'
                continue
            }
            $propsToRemove = [System.Collections.Generic.List[string]]::new()
            foreach ($prop in $SingleEnt.PSObject.Properties) {
                if ($null -eq $prop.Value) {
                    $propsToRemove.Add($prop.Name)
                }
            }
            foreach ($propName in $propsToRemove) {
                $SingleEnt.PSObject.Properties.Remove($propName)
            }
        }

        $Entities.Add($SingleEnt)
    }

    if ($Entities.Count -eq 0) {
        return
    }

    $Parameters = @{
        Context       = $Context
        Entity        = $Entities.ToArray()
        OperationType = $OperationType
        MaxRetries    = $MaxRetries
    }
    if ($Force) {
        $Parameters.Force = $Force
    }

    Update-AzDataTableEntity @Parameters -ErrorAction Stop
}

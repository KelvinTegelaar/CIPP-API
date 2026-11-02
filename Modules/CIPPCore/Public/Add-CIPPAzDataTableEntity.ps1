function Add-CIPPAzDataTableEntity {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Writes entities of any size to an Azure Table.
    .DESCRIPTION
    Thin wrapper around Add-AzDataTableLargeEntity (AzBobbyTables >= 3.6.2), which
    natively splits entities that exceed the table service size limits across
    multiple properties and rows, batches transactions, deduplicates entities by
    key and cleans up stale part rows when a split entity shrinks.

    Kept as a wrapper for backward compatibility with existing call sites and to
    strip null-valued properties, which the table service cannot store and the
    binary module rejects.

    On TableNotFound, invalidates the CreateTable cache, recreates the table, and
    retries once so a stale CIPPEnsuredTables entry cannot permanently break writes.
    #>
    [CmdletBinding(DefaultParameterSetName = 'OperationType')]
    param(
        $Context,
        $Entity,
        [switch]$CreateTableIfNotExists,

        [Parameter(ParameterSetName = 'Force')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'OperationType')]
        [ValidateSet('Add', 'UpsertMerge', 'UpsertReplace')]
        [string]$OperationType = 'Add'
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
        Context                = $Context
        Entity                 = $Entities.ToArray()
        CreateTableIfNotExists = $CreateTableIfNotExists
    }
    if ($PSCmdlet.ParameterSetName -eq 'Force') {
        $Parameters.Force = $Force
    } else {
        $Parameters.OperationType = $OperationType
    }

    try {
        Add-AzDataTableLargeEntity @Parameters -ErrorAction Stop
    } catch {
        if ($script:CIPPRepairingTable -or -not (Test-CIPPTableNotFound $_)) {
            throw
        }
        $script:CIPPRepairingTable = $true
        try {
            Repair-CIPPTable -Context $Context
            Add-AzDataTableLargeEntity @Parameters -ErrorAction Stop
        } finally {
            $script:CIPPRepairingTable = $false
        }
    }
}

function ConvertTo-CippStandardObject {
    param(
        [Parameter(Mandatory = $true)]
        $StandardObject
    )

    # If $StandardObject is an array (like for ConditionalAccessTemplate or IntuneTemplate),
    # we need to process each item individually.
    if ($StandardObject -is [System.Collections.IEnumerable] -and -not ($StandardObject -is [string])) {
        $ProcessedItems = New-Object System.Collections.ArrayList
        foreach ($Item in $StandardObject) {
            $ProcessedItems.Add((Convert-SingleStandardObject $Item)) | Out-Null
        }
        return [System.Collections.ArrayList]$ProcessedItems
    } else {
        # Single object scenario
        return Convert-SingleStandardObject $StandardObject
    }
}

function Convert-SingleStandardObject {
    param(
        [Parameter(Mandatory = $true)]
        $Obj
    )

    $Obj = [pscustomobject]$Obj

    $AllActionValues = @()
    if ($Obj.PSObject.Properties.Name -contains 'combinedActions') {
        $AllActionValues = $Obj.combinedActions
        $null = $Obj.PSObject.Properties.Remove('combinedActions')
    } elseif ($Obj.PSObject.Properties.Name -contains 'action') {
        if ($Obj.action -and $Obj.action.value) {
            $AllActionValues = $Obj.action.value
        }
        $null = $Obj.PSObject.Properties.Remove('action')
    }

    # Convert actions to booleans
    $Obj | Add-Member -NotePropertyName 'remediate' -NotePropertyValue ($AllActionValues -contains 'Remediate') -Force
    $Obj | Add-Member -NotePropertyName 'alert' -NotePropertyValue ($AllActionValues -contains 'warn') -Force
    $Obj | Add-Member -NotePropertyName 'report' -NotePropertyValue ($AllActionValues -contains 'Report') -Force

    # Flatten standards if present
    if ($Obj.PSObject.Properties.Name -contains 'standards' -and $Obj.standards) {
        foreach ($standardKey in $Obj.standards.PSObject.Properties.Name) {
            $NestedStandard = $Obj.standards.$standardKey
            if ($NestedStandard) {
                foreach ($nsProp in $NestedStandard.PSObject.Properties) {
                    $Obj | Add-Member -NotePropertyName $nsProp.Name -NotePropertyValue $nsProp.Value -Force
                }
            }
        }
        $null = $Obj.PSObject.Properties.Remove('standards')
    }

    return $Obj
}

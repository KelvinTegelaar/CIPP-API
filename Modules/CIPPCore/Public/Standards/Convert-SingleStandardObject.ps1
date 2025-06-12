function Convert-SingleStandardObject {
    param(
        [Parameter(Mandatory = $true)]
        $Obj
    )

    # Ensure we have a PSCustomObject we can modify
    $Obj = [pscustomobject]$Obj

    # Extract action arrays
    $AllActionValues = @()
    if ($Obj.PSObject.Properties.Name -contains 'combinedActions') {
        $AllActionValues = $Obj.combinedActions
        $Obj.PSObject.Properties.Remove('combinedActions') | Out-Null
    } elseif ($Obj.PSObject.Properties.Name -contains 'action') {
        if ($Obj.action -and $Obj.action.value) {
            $AllActionValues = $Obj.action.value
        }
        $Obj.PSObject.Properties.Remove('action') | Out-Null
    }

    # Convert to booleans
    $Obj | Add-Member -NotePropertyName 'remediate' -NotePropertyValue ($AllActionValues -contains 'Remediate') -Force
    $Obj | Add-Member -NotePropertyName 'alert' -NotePropertyValue ($AllActionValues -contains 'warn') -Force
    $Obj | Add-Member -NotePropertyName 'report' -NotePropertyValue ($AllActionValues -contains 'Report') -Force

    # Flatten "standards" if present
    if ($Obj.PSObject.Properties.Name -contains 'standards' -and $Obj.standards) {
        foreach ($standardKey in $Obj.standards.PSObject.Properties.Name) {
            $NestedStandard = $Obj.standards.$standardKey
            if ($NestedStandard) {
                foreach ($nsProp in $NestedStandard.PSObject.Properties) {
                    $Obj | Add-Member -NotePropertyName $nsProp.Name -NotePropertyValue $nsProp.Value -Force
                }
            }
        }
        $Obj.PSObject.Properties.Remove('standards') | Out-Null
    }

    return $Obj
}

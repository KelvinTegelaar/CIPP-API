function ConvertTo-CippStandardObject {
    param(
        [Parameter(Mandatory = $true)]
        $StandardObject
    )

    $StandardObject = [pscustomobject]$StandardObject

    $AllActionValues = @()
    if ($StandardObject.PSObject.Properties.Name -contains 'combinedActions') {
        $AllActionValues = $StandardObject.combinedActions
        $null = $StandardObject.PSObject.Properties.Remove('combinedActions')
    } elseif ($StandardObject.PSObject.Properties.Name -contains 'action') {
        $AllActionValues = $StandardObject.action.value
        $null = $StandardObject.PSObject.Properties.Remove('action')
    }

    $StandardObject | Add-Member -NotePropertyName 'remediate' -NotePropertyValue ($AllActionValues -contains 'Remediate') -Force
    $StandardObject | Add-Member -NotePropertyName 'alert' -NotePropertyValue ($AllActionValues -contains 'warn') -Force
    $StandardObject | Add-Member -NotePropertyName 'report' -NotePropertyValue ($AllActionValues -contains 'Report') -Force

    if ($StandardObject.PSObject.Properties.Name -contains 'standards' -and $StandardObject.standards) {
        foreach ($standardKey in $StandardObject.standards.PSObject.Properties.Name) {
            $NestedStandard = $StandardObject.standards.$standardKey
            if ($NestedStandard) {
                foreach ($nsProp in $NestedStandard.PSObject.Properties) {
                    $StandardObject | Add-Member -NotePropertyName $nsProp.Name -NotePropertyValue $nsProp.Value -Force
                }
            }
        }
        $null = $StandardObject.PSObject.Properties.Remove('standards')
    }

    return $StandardObject
}

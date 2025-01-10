
function Merge-CippStandards {
    param(
        [Parameter(Mandatory = $true)] $Existing,
        [Parameter(Mandatory = $true)] $CurrentStandard
    )
    $Existing = [pscustomobject]$Existing
    $CurrentStandard = [pscustomobject]$CurrentStandard
    $ExistingActionValues = @()
    if ($Existing.PSObject.Properties.Name -contains 'action') {
        if ($Existing.action -and $Existing.action.value) {
            $ExistingActionValues = @($Existing.action.value)
        }
        $null = $Existing.PSObject.Properties.Remove('action')
    }

    $CurrentActionValues = @()
    if ($CurrentStandard.PSObject.Properties.Name -contains 'action') {
        if ($CurrentStandard.action -and $CurrentStandard.action.value) {
            $CurrentActionValues = @($CurrentStandard.action.value)
        }
        $null = $CurrentStandard.PSObject.Properties.Remove('action')
    }
    $AllActionValues = ($ExistingActionValues + $CurrentActionValues) | Select-Object -Unique
    foreach ($prop in $CurrentStandard.PSObject.Properties) {
        if ($prop.Name -eq 'action') { continue }
        $Existing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }
    if ($AllActionValues.Count -gt 0) {
        $Existing | Add-Member -NotePropertyName 'combinedActions' -NotePropertyValue $AllActionValues -Force
    }

    return $Existing
}

function New-CIPPRestore {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Type = 'Scheduled',
        $RestoreValues,
        $APIName = 'CIPP Restore',
        $Headers
    )

    Write-Information "Scheduled Restore psproperties: $(([pscustomobject]$RestoreValues).psobject.Properties)"
    Write-LogMessage -headers $Headers -API $APINAME -message 'Restored backup' -Sev 'Debug'
    # Optional per-category item selection; a category without an entry restores everything in it.
    $ItemSelection = if ($RestoreValues.items) { [pscustomobject]$RestoreValues.items }
    $RestoreData = foreach ($ScheduledBackup in ([pscustomobject]$RestoreValues).psobject.Properties | Where-Object { $_.Value -eq $true -and $_.Name -notin 'email', 'webhook', 'psa', 'backup', 'overwrite', 'items' } | Select-Object -ExpandProperty Name) {
        Write-Information "Restoring $ScheduledBackup for tenant $TenantFilter"
        $TaskParams = @{ Task = $ScheduledBackup; TenantFilter = $TenantFilter; backup = $RestoreValues.backup; overwrite = $RestoreValues.overwrite; Headers = $Headers; APIName = $APIName }
        if ($ItemSelection -and $null -ne $ItemSelection.PSObject.Properties[$ScheduledBackup]) { $TaskParams.Items = @($ItemSelection.$ScheduledBackup) }
        New-CIPPRestoreTask @TaskParams
    }
    return $RestoreData
}


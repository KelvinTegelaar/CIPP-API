function New-CIPPRestore {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Type = 'Scheduled',
        $RestoreValues,
        $APIName = 'CIPP Restore',
        $ExecutingUser
    )

    Write-Host "Scheduled Restore psproperties: $(([pscustomobject]$RestoreValues).psobject.Properties)"
    Write-LogMessage -user $ExecutingUser -API $APINAME -message 'Restored backup' -Sev 'Debug'
    $RestoreData = foreach ($ScheduledBackup in ([pscustomobject]$RestoreValues).psobject.Properties.Name | Where-Object { $_ -notin 'email', 'webhook', 'psa', 'backup', 'overwrite' }) {
        New-CIPPRestoreTask -Task $ScheduledBackup -TenantFilter $TenantFilter -backup $RestoreValues.backup.value -overwrite $RestoreValues.overwrite
    }
    return $RestoreData
}


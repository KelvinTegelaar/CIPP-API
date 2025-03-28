function New-CIPPRestore {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Type = 'Scheduled',
        $RestoreValues,
        $APIName = 'CIPP Restore',
        $Headers
    )

    Write-Host "Scheduled Restore psproperties: $(([pscustomobject]$RestoreValues).psobject.Properties)"
    Write-LogMessage -headers $Headers -API $APINAME -message 'Restored backup' -Sev 'Debug'
    $RestoreData = foreach ($ScheduledBackup in ([pscustomobject]$RestoreValues).psobject.Properties.Name | Where-Object { $_ -notin 'email', 'webhook', 'psa', 'backup', 'overwrite' }) {
        New-CIPPRestoreTask -Task $ScheduledBackup -TenantFilter $TenantFilter -backup $RestoreValues.backup -overwrite $RestoreValues.overwrite -Headers $Headers -APIName $APIName
    }
    return $RestoreData
}


function Push-CIPPStandard {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $Item
    )

    Write-Information "Received queue item for $($Item.Tenant) and standard $($Item.Standard)."
    $Tenant = $Item.Tenant
    $Standard = $Item.Standard
    $FunctionName = 'Invoke-CIPPStandard{0}' -f $Standard
    Write-Information "We'll be running $FunctionName"
    $Rerun = Test-CIPPRerun -Type Standard -Tenant $Tenant -API "$($Standard)_$($Item.templateId)"
    if ($Rerun) {
        Write-Information 'Detected rerun. Exiting cleanly'
        exit 0
    } else {
        Write-Information "Rerun is set to false. We'll be running $FunctionName"
    }
    try {
        # Convert settings to JSON, replace %variables%, then convert back to object
        $SettingsJSON = $Item.Settings | ConvertTo-Json -Depth 10 -Compress
        if ($SettingsJSON -match '%') {
            $Settings = Get-CIPPTextReplacement -TenantFilter $Item.Tenant -Text $SettingsJSON | ConvertFrom-Json
        } else {
            $Settings = $Item.Settings
        }

        & $FunctionName -Tenant $Item.Tenant -Settings $Settings -ErrorAction Stop
        Write-Information "Standard $($Standard) completed for tenant $($Tenant)"
    } catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Error running standard $($Standard) for tenant $($Tenant) - $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        Write-Warning "Error running standard $($Standard) for tenant $($Tenant) - $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        throw $_.Exception.Message
    }
}

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

    if ($Standard -in @('IntuneTemplate', 'ConditionalAccessTemplate')) {
        $API = "$Standard_$($Item.templateId)_$($Item.Settings.TemplateList.value)"
    } else {
        $API = "$Standard_$($Item.templateId)"
    }

    $Rerun = Test-CIPPRerun -Type Standard -Tenant $Tenant -API $API
    if ($Rerun) {
        Write-Information 'Detected rerun. Exiting cleanly'
        exit 0
    } else {
        Write-Information "Rerun is set to false. We'll be running $FunctionName"
    }

    $StandardInfo = @{
        Standard           = $Standard
        StandardTemplateId = $Item.templateId
    }
    if ($Standard -eq 'IntuneTemplate') {
        $StandardInfo.IntuneTemplateId = $Item.Settings.TemplateList.value
    }
    if ($Standard -eq 'ConditionalAccessTemplate') {
        $StandardInfo.ConditionalAccessTemplateId = $Item.Settings.TemplateList.value
    }

    $Script:StandardInfo = $StandardInfo

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
    } finally {
        Remove-Variable -Name StandardInfo -Scope Script -ErrorAction SilentlyContinue
    }
}

function Invoke-CIPPStandardDisableViva {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentSetting = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$tenant/settings/peopleInsights" -tenantid $Tenant -AsApp $true

    If ($Settings.remediate -eq $true) {

        if ($CurrentSetting.isEnabledInOrganization -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Viva is already disabled.' -sev Info
        } else {
            try {
                # TODO This does not work. Throws an "EXCEPTION: Tenant admin role is required" error. Cant figure out how to fix -Bobby
                New-GraphPOSTRequest -Uri "https://graph.microsoft.com/beta/organization/$tenant/settings/peopleInsights" -tenantid $Tenant -AsApp $true -Type PATCH -Body '{"isEnabledInOrganization": false}' -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled Viva insights' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Viva for all users. Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentSetting.isEnabledInOrganization -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Viva is disabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Viva is not disabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableViva' -FieldValue $CurrentSetting.isEnabledInOrganization -StoreAs bool -Tenant $tenant
    }

}

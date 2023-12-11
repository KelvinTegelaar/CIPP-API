function Invoke-CIPPStandardDisableViva {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $currentsetting = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$tenant/settings/peopleInsights" -tenantid $Tenant -AsApp $true
    If ($Settings.remediate) {
        try {
            New-GraphPOSTRequest -Uri "https://graph.microsoft.com/beta/organization/$tenant/settings/peopleInsights" -tenantid $Tenant -AsApp $true -Type PATCH -Body '{"isEnabledInOrganization": false}' -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled Viva insights' -sev Info
    
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Viva for all users Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        if ($currentsetting.isEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Viva is disabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Viva is not disabled' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DisableViva' -FieldValue [bool]$currentsetting.isEnabled -StoreAs bool -Tenant $tenant
    }

}

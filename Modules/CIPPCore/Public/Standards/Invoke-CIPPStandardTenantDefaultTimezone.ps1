function Invoke-CIPPStandardTenantDefaultTimezone {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    $StateIsCorrect = $CurrentState.tenantDefaultTimezone -eq $Settings.Timezone

    If ($Settings.remediate) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Tenant Default Timezone is already set to $($Settings.Timezone)" -sev Info
        } else {
            try {
                New-GraphPostRequest -tenantid $tenant -uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type PATCH -Body "{`"tenantDefaultTimezone`": `"$($Settings.Timezone)`"}" -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Updated Tenant Default Timezone to $($Settings.Timezone)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set Tenant Default Timezone. Error: $($_.exception.message)" -sev Error
            }
        }

    }
    if ($Settings.alert) {

        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Tenant Default Timezone is set to $($Settings.Timezone)." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Tenant Default Timezone is not set to the desired value.' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'TenantDefaultTimezone' -FieldValue $CurrentState.tenantDefaultTimezone -StoreAs string -Tenant $tenant
    }
}

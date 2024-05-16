function Invoke-CIPPStandardTenantDefaultTimezone {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    $ExpectedTimezone = $Settings.Timezone.value
    $StateIsCorrect = $CurrentState.tenantDefaultTimezone -eq $ExpectedTimezone

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Tenant Default Timezone is already set to $ExpectedTimezone" -sev Info
        } else {
            try {
                New-GraphPostRequest -tenantid $tenant -uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type PATCH -Body "{`"tenantDefaultTimezone`": `"$ExpectedTimezone`"}" -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully updated Tenant Default Timezone to $ExpectedTimezone" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set Tenant Default Timezone. Error: $ErrorMessage" -sev Error
            }
        }

    }
    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Tenant Default Timezone is set to $ExpectedTimezone." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Tenant Default Timezone is not set to the desired value.' -sev Alert
        }
    }
    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TenantDefaultTimezone' -FieldValue $CurrentState.tenantDefaultTimezone -StoreAs string -Tenant $tenant
    }
}

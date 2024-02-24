function Invoke-CIPPStandardAnonReportDisable {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/reportSettings' -tenantid $Tenant -AsApp $true

    If ($Settings.remediate) {
        
        if ($CurrentInfo.displayConcealedNames -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports is already disabled.' -sev Info
        } else {
            try {
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/reportSettings' -Type patch -Body '{"displayConcealedNames": false}' -ContentType 'application/json' -AsApp $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports Disabled.' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable anonymous reports. Error: $($_.exception.message)" -sev Error
            }
        }
    }
    if ($Settings.alert) {

        if ($CurrentInfo.displayConcealedNames -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports is disabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Anonymous Reports is not disabled' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'AnonReport' -FieldValue [bool]$CurrentInfo.displayConcealedNames -StoreAs bool -Tenant $tenant
    }
}

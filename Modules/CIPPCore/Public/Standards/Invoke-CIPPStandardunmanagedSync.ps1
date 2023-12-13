function Invoke-CIPPStandardunmanagedSync {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        try {
            $body = '{"isUnmanagedSyncAppForTenantRestricted": false}'
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled Sync for unmanaged devices' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Sync for unmanaged devices: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
        if ($CurrentInfo.isUnmanagedSyncAppForTenantRestricted -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sync for unmanaged devices is disabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sync for unmanaged devices is not disabled' -sev Alert
        }
    }
    if ($Settings.report) {
        if ($CurrentInfo.isUnmanagedSyncAppForTenantRestricted -eq $false) {
            $CurrentInfo.isUnmanagedSyncAppForTenantRestricted = $true
        } else {
            $CurrentInfo.isUnmanagedSyncAppForTenantRestricted = $false
        }
        Add-CIPPBPAField -FieldName 'unmanagedSync' -FieldValue [bool]$CurrentInfo.isUnmanagedSyncAppForTenantRestricted -StoreAs bool -Tenant $tenant
    }
}

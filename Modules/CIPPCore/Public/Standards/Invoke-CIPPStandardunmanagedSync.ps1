function Invoke-CIPPStandardunmanagedSync {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) unmanagedSync
    .SYNOPSIS
        (Label) Only allow users to sync OneDrive from AAD joined devices
    .DESCRIPTION
        (Helptext) The unmanaged Sync standard has been temporarily disabled and does nothing.
        (DocsDescription) The unmanaged Sync standard has been temporarily disabled and does nothing.
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "highimpact"
        ADDEDCOMPONENT
        IMPACT
            High Impact
        POWERSHELLEQUIVALENT
            Update-MgAdminSharepointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.isUnmanagedSyncAppForTenantRestricted -eq $false) {
            try {
                #$body = '{"isUnmanagedSyncAppForTenantRestricted": true}'
                #$null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'The unmanaged Sync standard has been temporarily disabled.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Sync for unmanaged devices: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sync for unmanaged devices is already disabled' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.isUnmanagedSyncAppForTenantRestricted -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sync for unmanaged devices is disabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sync for unmanaged devices is not disabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'unmanagedSync' -FieldValue $CurrentInfo.isUnmanagedSyncAppForTenantRestricted -StoreAs bool -Tenant $tenant
    }
}

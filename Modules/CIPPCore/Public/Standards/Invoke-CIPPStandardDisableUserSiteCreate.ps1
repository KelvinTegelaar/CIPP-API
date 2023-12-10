function Invoke-CIPPStandardDisableUserSiteCreate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        try {
            $body = '{"isSiteCreationEnabled": false}'
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled standard users from creating sites' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable standard users from creating sites: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
        if ($CurrentInfo.isSiteCreationEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Standard users are not allowed to create sites' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Standard users are allowed to create sites' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DisableUserSiteCreate' -FieldValue [bool]$CurrentInfo.isSiteCreationEnabled -StoreAs bool -Tenant $tenant
    }
}
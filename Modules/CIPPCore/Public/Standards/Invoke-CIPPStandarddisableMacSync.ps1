function Invoke-CIPPStandarddisableMacSync {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    disableMacSync
    .CAT
    SharePoint Standards
    .TAG
    "highimpact"
    .HELPTEXT
    Disables the ability for Mac devices to sync with OneDrive.
    .ADDEDCOMPONENT
    .LABEL
    Do not allow Mac devices to sync using OneDrive
    .IMPACT
    High Impact
    .POWERSHELLEQUIVALENT
    Update-MgAdminSharepointSetting
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Disables the ability for Mac devices to sync with OneDrive.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.isMacSyncAppEnabled -eq $true) {
            try {
                $body = '{"isMacSyncAppEnabled": false}'
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled Mac OneDrive Sync' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Mac OneDrive Sync: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Mac OneDrive Sync is already disabled' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.isMacSyncAppEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Mac OneDrive Sync is disabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Mac OneDrive Sync is not disabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentInfo.isMacSyncAppEnabled = -not $CurrentInfo.isMacSyncAppEnabled
        Add-CIPPBPAField -FieldName 'MacSync' -FieldValue $CurrentInfo.isMacSyncAppEnabled -StoreAs bool -Tenant $tenant
    }
}





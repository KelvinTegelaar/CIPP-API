function Invoke-CIPPStandarddisableMacSync {
    <#
    .FUNCTIONALITY
    Internal
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
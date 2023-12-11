function Invoke-CIPPStandardSendFromAlias {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        try {
            $AdminAuditLogParams = @{
                SendFromAliasEnabled = $true
            }
            New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams $AdminAuditLogParams
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias Enabled.' -sev Info

        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Send from Alias Standard. Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig')
        if ($CurrentInfo.SendFromAliasEnabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is not enabled.' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'SendFromAlias' -FieldValue [bool]$CurrentInfo.SendFromAliasEnabled -StoreAs bool -Tenant $tenant
    }
}

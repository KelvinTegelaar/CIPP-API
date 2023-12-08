function Invoke-sharingCapability {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.Remediate) {
        

    try {
        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body "{`"sharingCapability`":`"$($Settings.Level)`"}" -ContentType 'application/json'
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Set sharing level to $($Settings.level)" -sev Info
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set sharing level to $($Settings.level): $($_.exception.message)" -sev Error
    }
}
}

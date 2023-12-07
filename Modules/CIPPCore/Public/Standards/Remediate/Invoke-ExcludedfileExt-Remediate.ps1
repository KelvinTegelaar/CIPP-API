function Invoke-ExcludedfileExt-Remediate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    try {
        $Exts = $Settings.ext -split ','
        $body = ConvertTo-Json -InputObject @{ excludedFileExtensionsForSyncApp = @($Exts) }
        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Added $($Settings.ext) to excluded synced files" -sev Info
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to add $($Settings.ext) to excluded synced files: $($_.exception.message)" -sev Error
    }
}

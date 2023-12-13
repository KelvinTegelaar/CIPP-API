function Invoke-CIPPStandardExcludedfileExt {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $Exts = $Settings.ext -split ','
    If ($Settings.remediate) {
        

        try {
            $body = ConvertTo-Json -InputObject @{ excludedFileExtensionsForSyncApp = @($Exts) }
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Added $($Settings.ext) to excluded synced files" -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to add $($Settings.ext) to excluded synced files: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
        if ($CurrentInfo.excludedFileExtensionsForSyncApp -contains $Exts) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Excluded synced files contains $($Settings.ext)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Excluded synced files does not contain $($Settings.ext)" -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'ExcludedfileExt' -FieldValue $CurrentInfo.excludedFileExtensionsForSyncApp -StoreAs json -Tenant $tenant
    }
}

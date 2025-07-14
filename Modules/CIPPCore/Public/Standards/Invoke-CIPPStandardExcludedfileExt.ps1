function Invoke-CIPPStandardExcludedfileExt {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ExcludedfileExt
    .SYNOPSIS
        (Label) Exclude File Extensions from Syncing
    .DESCRIPTION
        (Helptext) Sets the file extensions that are excluded from syncing with OneDrive. These files will be blocked from upload. '*.' is automatically added to the extension and can be omitted.
        (DocsDescription) Sets the file extensions that are excluded from syncing with OneDrive. These files will be blocked from upload. '\*.' is automatically added to the extension and can be omitted.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.ExcludedfileExt.ext","label":"Extensions, Comma separated"}
        IMPACT
            High Impact
        ADDEDDATE
            2022-06-15
        POWERSHELLEQUIVALENT
            Update-MgAdminSharePointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    Test-CIPPStandardLicense -StandardName 'ExcludedfileExt' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'ExcludedfileExt'

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    $Exts = ($Settings.ext -replace ' ', '') -split ','
    # Add a wildcard to the extensions since thats what the SP admin center does
    $Exts = $Exts | ForEach-Object { if ($_ -notlike '*.*') { "*.$_" } else { $_ } }


    $MissingExclusions = foreach ($Exclusion in $Exts) {
        if ($Exclusion -notin $CurrentInfo.excludedFileExtensionsForSyncApp) {
            $Exclusion
        }
    }

    Write-Host "MissingExclusions: $($MissingExclusions)"


    If ($Settings.remediate -eq $true) {

        # If the number of extensions in the settings does not match the number of extensions in the current settings, we need to update the settings
        $MissingExclusions = if ($Exts.Count -ne $CurrentInfo.excludedFileExtensionsForSyncApp.Count) { $true } else { $MissingExclusions }
        if ($MissingExclusions) {
            Write-Host "CurrentInfo.excludedFileExtensionsForSyncApp: $($CurrentInfo.excludedFileExtensionsForSyncApp)"
            Write-Host "Exts: $($Exts)"
            try {
                $body = ConvertTo-Json -InputObject @{ excludedFileExtensionsForSyncApp = @($Exts) }
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Added $($Settings.ext) to excluded synced files" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to add $($Settings.ext) to excluded synced files: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Excluded synced files already contains $($Settings.ext)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($MissingExclusions) {
            Write-StandardsAlert -message 'Exclude File Extensions from Syncing missing some extensions.' -object $MissingExclusions -tenant $Tenant -standardName 'ExcludedfileExt' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Excluded synced files does not contain $($MissingExclusions -join ',')" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Excluded synced files contains $($Settings.ext)" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $MissingExclusions ? (@{ ext = $CurrentInfo.excludedFileExtensionsForSyncApp -join ',' }): $true
        Set-CIPPStandardsCompareField -FieldName 'standards.ExcludedfileExt' -FieldValue $state -Tenant $tenant
        Add-CIPPBPAField -FieldName 'ExcludedfileExt' -FieldValue $CurrentInfo.excludedFileExtensionsForSyncApp -StoreAs json -Tenant $tenant
    }
}

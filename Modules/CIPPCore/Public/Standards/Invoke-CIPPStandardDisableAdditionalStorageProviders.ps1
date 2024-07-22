function Invoke-CIPPStandardDisableAdditionalStorageProviders {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableAdditionalStorageProviders
    .SYNOPSIS
        (Label) Disable additional storage providers in OWA
    .DESCRIPTION
        (Helptext) Disables the ability for users to open files in Outlook on the Web, from other providers such as Box, Dropbox, Facebook, Google Drive, OneDrive Personal, etc.
        (DocsDescription) Disables additional storage providers in OWA. This is to prevent users from using personal storage providers like Dropbox, Google Drive, etc. Usually this has little user impact.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "lowimpact"
            "CIS"
            "exo_storageproviderrestricted"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Get-OwaMailboxPolicy \| Set-OwaMailboxPolicy -AdditionalStorageProvidersEnabled \$False
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $AdditionalStorageProvidersState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OwaMailboxPolicy' -cmdParams @{Identity = 'OwaMailboxPolicy-Default' }

    if ($Settings.remediate -eq $true) {

        try {
            if ($AdditionalStorageProvidersState.AdditionalStorageProvidersAvailable) {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OwaMailboxPolicy' -cmdParams @{ Identity = $AdditionalStorageProvidersState.Identity; AdditionalStorageProvidersAvailable = $false } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'OWA additional storage providers have been disabled.' -sev Info
                $AdditionalStorageProvidersState.AdditionalStorageProvidersAvailable = $false
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'OWA additional storage providers are already disabled.' -sev Info
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable OWA additional storage providers. Error: $ErrorMessage" -sev Error
        }

    }

    if ($Settings.alert -eq $true) {
        if ($AdditionalStorageProvidersState.AdditionalStorageProvidersAvailable) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'OWA additional storage providers are enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'OWA additional storage providers are disabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AdditionalStorageProvidersEnabled' -FieldValue $AdditionalStorageProvidersState.AdditionalStorageProvidersEnabled -StoreAs bool -Tenant $tenant
    }
}

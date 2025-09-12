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
            "CIS"
            "exo_storageproviderrestricted"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-01-17
        POWERSHELLEQUIVALENT
            Get-OwaMailboxPolicy \| Set-OwaMailboxPolicy -AdditionalStorageProvidersEnabled \$False
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableAdditionalStorageProviders' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableAdditionalStorageProviders'

    try {
        $AdditionalStorageProvidersState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OwaMailboxPolicy' -cmdParams @{Identity = 'OwaMailboxPolicy-Default' } -Select 'Identity, AdditionalStorageProvidersAvailable'
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableAddShortcutsToOneDrive state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {

        try {
            if ($AdditionalStorageProvidersState.AdditionalStorageProvidersAvailable) {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OwaMailboxPolicy' -cmdParams @{ Identity = $AdditionalStorageProvidersState.Identity; AdditionalStorageProvidersAvailable = $false } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'OWA additional storage providers has been disabled.' -sev Info
                $AdditionalStorageProvidersState.AdditionalStorageProvidersAvailable = $false
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'OWA additional storage providers are already disabled.' -sev Info
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable OWA additional storage providers. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }

    }

    if ($Settings.alert -eq $true) {
        if ($AdditionalStorageProvidersState.AdditionalStorageProvidersAvailable) {
            $Object = $AdditionalStorageProvidersState | Select-Object -Property AdditionalStorageProvidersAvailable
            Write-StandardsAlert -message 'OWA additional storage providers are enabled' -object $Object -tenant $Tenant -standardName 'DisableAdditionalStorageProviders' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'OWA additional storage providers are enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'OWA additional storage providers are disabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $State = $AdditionalStorageProvidersState.AdditionalStorageProvidersEnabled ? $false : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableAdditionalStorageProviders' -FieldValue $State -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AdditionalStorageProvidersEnabled' -FieldValue $State -StoreAs bool -Tenant $Tenant
    }
}

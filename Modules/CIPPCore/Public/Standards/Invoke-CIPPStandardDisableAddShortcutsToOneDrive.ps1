function Invoke-CIPPStandardDisableAddShortcutsToOneDrive {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableAddShortcutsToOneDrive
    .SYNOPSIS
        (Label) Set Add Shortcuts To OneDrive button state
    .DESCRIPTION
        (Helptext) If disabled, the button Add shortcut to OneDrive will be removed and users in the tenant will no longer be able to add new shortcuts to their OneDrive. Existing shortcuts will remain functional
        (DocsDescription) If disabled, the button Add shortcut to OneDrive will be removed and users in the tenant will no longer be able to add new shortcuts to their OneDrive. Existing shortcuts will remain functional
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "mediumimpact"
        ADDEDCOMPONENT
            {"type":"Select","label":"Add Shortcuts To OneDrive button state","name":"standards.DisableAddShortcutsToOneDrive.state","values":[{"label":"Disabled","value":"true"},{"label":"Enabled","value":"false"}]}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DisableAddShortcutsToOneDrive \$true or \$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableAddShortcutsToOneDrive'

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant | Select-Object _ObjectIdentity_, TenantFilter, DisableAddToOneDrive

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'OneDriveAddShortcutButtonDisabled' -FieldValue $CurrentState.DisableAddToOneDrive -StoreAs bool -Tenant $Tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'DisableAddShortcutsToOneDrive: Invalid state parameter set' -sev Error
        Return
    }

    $WantedState = [System.Convert]::ToBoolean($Settings.state)
    $StateIsCorrect = if ($CurrentState.DisableAddToOneDrive -eq $WantedState) { $true } else { $false }
    $HumanReadableState = if ($WantedState -eq $true) { 'disabled' } else { 'enabled' }

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($StateIsCorrect -eq $false) {
            try {
                $CurrentState | Set-CIPPSPOTenant -Properties @{DisableAddToOneDrive = $WantedState }
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set the Add Shortcuts To OneDrive Button to $HumanReadableState" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set the Add Shortcuts To OneDrive Button to $HumanReadableState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The Add Shortcuts To OneDrive Button is already set to the wanted of $HumanReadableState" -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The Add Shortcuts To OneDrive Button is already set to the wanted state of $HumanReadableState" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The Add Shortcuts To OneDrive Button Button is not set to the wanted state of $HumanReadableState" -sev Alert
        }
    }


}

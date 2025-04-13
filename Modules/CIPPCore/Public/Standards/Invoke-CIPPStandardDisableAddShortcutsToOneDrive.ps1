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
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Add Shortcuts To OneDrive button state","name":"standards.DisableAddShortcutsToOneDrive.state","options":[{"label":"Disabled","value":"true"},{"label":"Enabled","value":"false"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2023-07-25
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DisableAddShortcutsToOneDrive \$true or \$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/sharepoint-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableAddShortcutsToOneDrive'

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant | Select-Object _ObjectIdentity_, TenantFilter, DisableAddToOneDrive

    # Input validation
    $StateValue = $Settings.state.value ?? $Settings.state
    if (([string]::IsNullOrWhiteSpace($StateValue) -or $StateValue -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'DisableAddShortcutsToOneDrive: Invalid state parameter set' -sev Error
        Return
    }

    $WantedState = [System.Convert]::ToBoolean($StateValue)
    $StateIsCorrect = if ($CurrentState.DisableAddToOneDrive -eq $WantedState) { $true } else { $false }
    $HumanReadableState = if ($WantedState -eq $true) { 'disabled' } else { 'enabled' }

    if ($Settings.report -eq $true) {
        if ($StateIsCorrect -eq $true) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState | Select-Object -Property DisableAddToOneDrive
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableAddShortcutsToOneDrive' -FieldValue $FieldValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'OneDriveAddShortcutButtonDisabled' -FieldValue $CurrentState.DisableAddToOneDrive -StoreAs bool -Tenant $Tenant
    }

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
            Write-StandardsAlert -message "The Add Shortcuts To OneDrive Button is not set to the wanted state of $HumanReadableState" -object $CurrentState -tenant $tenant -standardName 'DisableAddShortcutsToOneDrive' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The Add Shortcuts To OneDrive Button Button is not set to the wanted state of $HumanReadableState" -sev Info
        }
    }


}

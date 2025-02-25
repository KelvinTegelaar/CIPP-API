function Invoke-CIPPStandardSPSyncButtonState {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPSyncButtonState
    .SYNOPSIS
        (Label) Set SharePoint sync button state
    .DESCRIPTION
        (Helptext) If disabled, users in the tenant will no longer be able to use the Sync button to sync SharePoint content on all sites. However, existing synced content will remain functional on the user's computer.
        (DocsDescription) If disabled, users in the tenant will no longer be able to use the Sync button to sync SharePoint content on all sites. However, existing synced content will remain functional on the user's computer.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"SharePoint Sync Button state","name":"standards.SPSyncButtonState.state","options":[{"label":"Disabled","value":"true"},{"label":"Enabled","value":"false"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-26
        POWERSHELLEQUIVALENT
            Set-SPOTenant -HideSyncButtonOnTeamSite \$true or \$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/sharepoint-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SPSyncButtonState'

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant | Select-Object _ObjectIdentity_, TenantFilter, HideSyncButtonOnDocLib

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SPSyncButtonDisabled' -FieldValue $CurrentState.HideSyncButtonOnDocLib -StoreAs bool -Tenant $Tenant
    }

    # Input validation
    $StateValue = $Settings.state.value ?? $Settings.state
    if (([string]::IsNullOrWhiteSpace($StateValue) -or $StateValue -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'SPSyncButtonState: Invalid state parameter set' -sev Error
        Return
    }

    $WantedState = [System.Convert]::ToBoolean($StateValue)
    $StateIsCorrect = if ($CurrentState.HideSyncButtonOnDocLib -eq $WantedState) { $true } else { $false }
    $HumanReadableState = if ($WantedState -eq $true) { 'disabled' } else { 'enabled' }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($StateIsCorrect -eq $false) {
            try {
                $CurrentState | Set-CIPPSPOTenant -Properties @{HideSyncButtonOnDocLib = $WantedState }
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set the SharePoint Sync Button state to $HumanReadableState" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set the SharePoint Sync Button state to $HumanReadableState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The SharePoint Sync Button is already set to the wanted state of $HumanReadableState" -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The SharePoint Sync Button is already set to the wanted state of $HumanReadableState" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The SharePoint Sync Button is not set to the wanted state of $HumanReadableState" -sev Alert
        }
    }
}

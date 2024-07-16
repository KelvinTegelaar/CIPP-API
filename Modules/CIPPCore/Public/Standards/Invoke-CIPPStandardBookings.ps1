function Invoke-CIPPStandardBookings {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) Bookings
    .SYNOPSIS
        (Label) Set Bookings state
    .DESCRIPTION
        (Helptext) Sets the state of Bookings on the tenant. Bookings is a scheduling tool that allows users to book appointments with others both internal and external.
        (DocsDescription) Sets the state of Bookings on the tenant. Bookings is a scheduling tool that allows users to book appointments with others both internal and external.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "mediumimpact"
        ADDEDCOMPONENT
            {"type":"Select","label":"Select value","name":"standards.Bookings.state","values":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -BookingsEnabled
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)

    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').BookingsEnabled
    $WantedState = if ($Settings.state -eq 'true') { $true } else { $false }
    $StateIsCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    if ($Settings.report -eq $true) {
        # Default is not set, not set means it's enabled
        if ($null -eq $CurrentState ) { $CurrentState = $true }
        Add-CIPPBPAField -FieldName 'BookingsState' -FieldValue $CurrentState -StoreAs bool -Tenant $tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'BookingsEnabled: Invalid state parameter set' -sev Error
        Return
    }
    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateIsCorrect -eq $false) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ BookingsEnabled = $WantedState } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set the tenant Bookings state to $($Settings.state)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set the tenant Bookings state to $($Settings.state). Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant Bookings state is already set correctly to $($Settings.state)" -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant Bookings is set correctly to $($Settings.state)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant Bookings is not set correctly to $($Settings.state)" -sev Alert
        }
    }



}

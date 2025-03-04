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
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Select value","name":"standards.Bookings.state","options":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-05-31
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -BookingsEnabled
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'Bookings'

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state

    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').BookingsEnabled
    $WantedState = if ($state -eq 'true') { $true } else { $false }
    $StateIsCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    if ($Settings.report -eq $true) {
        # Default is not set, not set means it's enabled
        if ($null -eq $CurrentState ) { $CurrentState = $true }
        Add-CIPPBPAField -FieldName 'BookingsState' -FieldValue $CurrentState -StoreAs bool -Tenant $Tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'BookingsEnabled: Invalid state parameter set' -sev Error
        Return
    }
    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateIsCorrect -eq $false) {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ BookingsEnabled = $WantedState } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set the tenant Bookings state to $state" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set the tenant Bookings state to $state. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The tenant Bookings state is already set correctly to $state" -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The tenant Bookings is set correctly to $state" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The tenant Bookings is not set correctly to $state" -sev Alert
        }
    }



}

function Invoke-CIPPStandardTeamsMeetingsByDefault {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsMeetingsByDefault
    .SYNOPSIS
        (Label) Set Teams Meetings by default state
    .DESCRIPTION
        (Helptext) Sets the default state for automatically turning meetings into Teams meetings for the tenant. This can be overridden by the user in Outlook.
        (DocsDescription) Sets the default state for automatically turning meetings into Teams meetings for the tenant. This can be overridden by the user in Outlook.
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.TeamsMeetingsByDefault.state","options":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-05-31
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -OnlineMeetingsByDefaultEnabled
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsMeetingsByDefault'

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state

    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').OnlineMeetingsByDefaultEnabled
    $WantedState = if ($state -eq 'true') { $true } else { $false }
    $StateIsCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'TeamsMeetingsByDefault: Invalid state parameter set' -sev Error
        Return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateIsCorrect -eq $false) {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ OnlineMeetingsByDefaultEnabled = $WantedState } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set the tenant TeamsMeetingsByDefault state to $state" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set the tenant TeamsMeetingsByDefault state to $state. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The tenant TeamsMeetingsByDefault state is already set correctly to $state" -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The tenant TeamsMeetingsByDefault is set correctly to $state" -sev Info
        } else {
            Write-StandardsAlert -message "The tenant TeamsMeetingsByDefault is not set correctly to $state" -object @{CurrentState = $CurrentState; WantedState = $WantedState} -tenant $Tenant -standardName 'TeamsMeetingsByDefault' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The tenant TeamsMeetingsByDefault is not set correctly to $state" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        # Default is not set, not set means it's enabled
        if ($null -eq $CurrentState ) { $CurrentState = $true }
        Add-CIPPBPAField -FieldName 'TeamsMeetingsByDefault' -FieldValue $CurrentState -StoreAs bool -Tenant $Tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsMeetingsByDefault' -FieldValue $FieldValue -Tenant $Tenant
    }
}

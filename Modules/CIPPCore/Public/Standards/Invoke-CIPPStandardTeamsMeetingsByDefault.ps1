function Invoke-CIPPStandardTeamsMeetingsByDefault {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    TeamsMeetingsByDefault
    .CAT
    Exchange Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Sets the default state for automatically turning meetings into Teams meetings for the tenant. This can be overridden by the user in Outlook.
    .ADDEDCOMPONENT
    {"type":"Select","label":"Select value","name":"standards.TeamsMeetingsByDefault.state","values":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
    .LABEL
    Set Teams Meetings by default state
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Set-OrganizationConfig -OnlineMeetingsByDefaultEnabled
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Sets the default state for automatically turning meetings into Teams meetings for the tenant. This can be overridden by the user in Outlook.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').OnlineMeetingsByDefaultEnabled
    $WantedState = if ($Settings.state -eq 'true') { $true } else { $false }
    $StateIsCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    if ($Settings.report -eq $true) {
        # Default is not set, not set means it's enabled
        if ($null -eq $CurrentState ) { $CurrentState = $true }
        Add-CIPPBPAField -FieldName 'TeamsMeetingsByDefault' -FieldValue $CurrentState -StoreAs bool -Tenant $tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'TeamsMeetingsByDefault: Invalid state parameter set' -sev Error
        Return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateIsCorrect -eq $false) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ OnlineMeetingsByDefaultEnabled = $WantedState } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set the tenant TeamsMeetingsByDefault state to $($Settings.state)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set the tenant TeamsMeetingsByDefault state to $($Settings.state). Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant TeamsMeetingsByDefault state is already set correctly to $($Settings.state)" -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant TeamsMeetingsByDefault is set correctly to $($Settings.state)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant TeamsMeetingsByDefault is not set correctly to $($Settings.state)" -sev Alert
        }
    }
}





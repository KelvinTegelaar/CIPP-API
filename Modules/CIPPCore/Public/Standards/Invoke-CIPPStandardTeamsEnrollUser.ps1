Function Invoke-CIPPStandardTeamsEnrollUser {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsEnrollUser
    .SYNOPSIS
        (Label) Default voice and face enrollment
    .DESCRIPTION
        (Helptext) Controls whether users with this policy can set the voice profile capture and enrollment through the Recognition tab in their Teams client settings.
        (DocsDescription) Controls whether users with this policy can set the voice profile capture and enrollment through the Recognition tab in their Teams client settings.
    .NOTES
        CAT
            Teams Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"standards.TeamsEnrollUser.EnrollUserOverride","label":"Voice and Face Enrollment","options":[{"label":"Disabled","value":"Disabled"},{"label":"Enabled","value":"Enabled"}]}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -Identity Global -EnrollUserOverride \$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/teams-standards#low-impact
    #>

    param($Tenant, $Settings)

    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{Identity = 'Global' }
    | Select-Object EnrollUserOverride

    $StateIsCorrect = ($CurrentState.EnrollUserOverride -eq $Settings.EnrollUserOverride.value)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams Enroll User Override settings already set to $($Settings.EnrollUserOverride.value)." -sev Info
        } else {
            $cmdparams = @{
                Identity           = 'Global'
                EnrollUserOverride = $Settings.EnrollUserOverride.value
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' -CmdParams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Teams Enroll User Override setting to $($Settings.EnrollUserOverride.value)." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Enroll User Override setting to $($Settings.EnrollUserOverride.value)." -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Enroll User Override settings is set correctly.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Enroll User Override settings is not set correctly.' -sev Alert
        }
    }

    if ($Setings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsEnrollUser' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}

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
        ADDEDCOMPONENT
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsEnrollUser.EnrollUserOverride","label":"Voice and Face Enrollment","options":[{"label":"Disabled","value":"Disabled"},{"label":"Enabled","value":"Enabled"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-11-12
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -Identity Global -EnrollUserOverride \$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/teams-standards#low-impact
    #>

    param($Tenant, $Settings)

    # Get EnrollUserOverride value using null-coalescing operator
    $enrollUserOverride = $Settings.EnrollUserOverride.value ?? $Settings.EnrollUserOverride

    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -cmdParams @{Identity = 'Global' }
    | Select-Object EnrollUserOverride

    $StateIsCorrect = ($CurrentState.EnrollUserOverride -eq $enrollUserOverride)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams Enroll User Override settings already set to $enrollUserOverride." -sev Info
        } else {
            $cmdParams = @{
                Identity           = 'Global'
                EnrollUserOverride = $enrollUserOverride
            }

            try {
                $null = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' -cmdParams $cmdParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Teams Enroll User Override setting to $enrollUserOverride." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Enroll User Override setting to $enrollUserOverride." -sev Error -LogData $ErrorMessage
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

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsEnrollUser' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}

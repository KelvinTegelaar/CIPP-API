function Invoke-CIPPStandardTeamsGuestAccess {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsGuestAccess
    .SYNOPSIS
        (Label) Allow guest users in Teams
    .DESCRIPTION
        (Helptext) Allow guest users access to teams.
        (DocsDescription) Allow guest users access to teams. Guest users are users who are not part of your organization but have been invited to collaborate with your organization in Teams. This setting allows you to control whether guest users can access Teams.
    .NOTES
        CAT
            Teams Standards
        TAG
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsGuestAccess.AllowGuestUser","label":"Allow guest users"}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-06-03
        POWERSHELLEQUIVALENT
            Set-CsTeamsClientConfiguration -AllowGuestUser \$true
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsClientConfiguration' -CmdParams @{Identity = 'Global' } | Select-Object AllowGuestUser

    if ($null -eq $Settings.AllowGuestUser) { $Settings.AllowGuestUser = $false }

    $StateIsCorrect = ($CurrentState.AllowGuestUser -eq $Settings.AllowGuestUser)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Guest Access already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity       = 'Global'
                AllowGuestUser = $Settings.AllowGuestUser
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsClientConfiguration' -CmdParams $cmdParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Teams Guest Access settings' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Guest Access settings. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Guest Access settings is set correctly.' -sev Info
        } else {
            Write-StandardsAlert -message 'Teams Guest Access settings is not set correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsGuestAccess' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Guest Access settings is not set correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsGuestAccess' -FieldValue $FieldValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsGuestAccess' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

    }
}

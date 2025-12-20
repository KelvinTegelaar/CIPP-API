function Invoke-CIPPStandardTeamsExternalChatWithAnyone {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsExternalChatWithAnyone
    .SYNOPSIS
        (Label) Set Teams chat with anyone setting
    .DESCRIPTION
        (Helptext) Controls whether users can start Teams chats with any email address, inviting external recipients as guests via email.
        (DocsDescription) Manages the Teams messaging policy setting UseB2BInvitesToAddExternalUsers. When enabled, users can start chats with any email address and recipients receive an invitation to join the chat as guests. Disabling the setting prevents these external email chats from being created, keeping conversations limited to internal users and approved guests.
    .NOTES
        CAT
            Teams Standards
        TAG
        EXECUTIVETEXT
            Allows organizations to decide if employees can launch Microsoft Teams chats with anyone on the internet using just an email address. Disabling the feature keeps conversations inside trusted boundaries and helps prevent accidental data exposure through unexpected external invitations.
        ADDEDCOMPONENT
            {"type":"radio","name":"standards.TeamsExternalChatWithAnyone.UseB2BInvitesToAddExternalUsers","label":"Allow chatting with anyone via email","options":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}],"defaultValue":"Disabled"}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-11-03
        POWERSHELLEQUIVALENT
            Set-CsTeamsMessagingPolicy -Identity Global -UseB2BInvitesToAddExternalUsers \$false/\$true
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsExternalChatWithAnyone' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    }

    try {
        $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMessagingPolicy' -CmdParams @{ Identity = 'Global' } | Select-Object -Property Identity, UseB2BInvitesToAddExternalUsers
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the Teams external chat state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Set default to Disabled if not specified. Should not be possible without some serious misconfiguration via the API
    $Settings.UseB2BInvitesToAddExternalUsers ??= $false
    $DesiredState = [System.Convert]::ToBoolean($Settings.UseB2BInvitesToAddExternalUsers)
    $StateIsCorrect = ($CurrentState.UseB2BInvitesToAddExternalUsers -eq $DesiredState)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams external chat with anyone setting already set to: $DesiredState" -sev Info
        } else {
            $cmdParams = @{
                Identity                        = 'Global'
                UseB2BInvitesToAddExternalUsers = $DesiredState
            }

            try {
                $null = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMessagingPolicy' -CmdParams $cmdParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully updated Teams external chat with anyone setting to UseB2BInvitesToAddExternalUsers: $DesiredState" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to configure Teams external chat with anyone setting. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams external chat setting is configured correctly as: $DesiredState" -sev Info
        } else {
            Write-StandardsAlert -message 'Teams external chat setting is not configured correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsExternalChatWithAnyone' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams external chat setting is not configured correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsExternalChatWithAnyone' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsExternalChatWithAnyone' -FieldValue $FieldValue -Tenant $Tenant
    }
}

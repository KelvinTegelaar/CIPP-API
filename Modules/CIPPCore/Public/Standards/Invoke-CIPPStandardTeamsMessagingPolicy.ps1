Function Invoke-CIPPStandardTeamsMessagingPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsMessagingPolicy
    .SYNOPSIS
        (Label) Global Messaging Policy for Microsoft Teams
    .DESCRIPTION
        (Helptext) Sets the properties of the Global messaging policy.
        (DocsDescription) Sets the properties of the Global messaging policy. Messaging policies control which chat and channel messaging features are available to users in Teams.
    .NOTES
        CAT
            Teams Standards
        TAG
            "mediumimpact"
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsMessagingPolicy.AllowOwnerDeleteMessage","label":"Allow Owner to Delete Messages","default":false}
            {"type":"switch","name":"standards.TeamsMessagingPolicy.AllowUserDeleteMessage","label":"Allow User to Delete Messages","default":true}
            {"type":"switch","name":"standards.TeamsMessagingPolicy.AllowUserEditMessage","label":"Allow User to Edit Messages","default":true}
            {"type":"switch","name":"standards.TeamsMessagingPolicy.AllowUserDeleteChat","label":"Allow User to Delete Chats","default":true}
            {"type":"autoComplete","multiple":false,"name":"standards.TeamsMessagingPolicy.ReadReceiptsEnabledType","label":"Read Receipts Enabled Type","options":[{"label":"User controlled","value":"UserPreference"},{"label":"Turned on for everyone","value":"Everyone"},{"label":"Turned off for everyone","value":"None"}]}
            {"type":"switch","name":"standards.TeamsMessagingPolicy.CreateCustomEmojis","label":"Allow Creating Custom Emojis","default":true}
            {"type":"switch","name":"standards.TeamsMessagingPolicy.DeleteCustomEmojis","label":"Allow Deleting Custom Emojis","default":false}
            {"type":"switch","name":"standards.TeamsMessagingPolicy.AllowSecurityEndUserReporting","label":"Allow reporting message as security concern","default":true}
            {"type":"switch","name":"standards.TeamsMessagingPolicy.AllowCommunicationComplianceEndUserReporting","label":"Allow reporting message as inappropriate content","default":true}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-CsTeamsMessagingPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/teams-standards#medium-impact
    #>
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsMessagingPolicy'

    param($Tenant, $Settings)
    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMessagingPolicy' -CmdParams @{Identity = 'Global' }

    if ($null -eq $Settings.AllowOwnerDeleteMessage) { $Settings.AllowOwnerDeleteMessage = $CurrentState.AllowOwnerDeleteMessage }
    if ($null -eq $Settings.AllowUserDeleteMessage) { $Settings.AllowUserDeleteMessage = $CurrentState.AllowUserDeleteMessage }
    if ($null -eq $Settings.AllowUserEditMessage) { $Settings.AllowUserEditMessage = $CurrentState.AllowUserEditMessage }
    if ($null -eq $Settings.AllowUserDeleteChat) { $Settings.AllowUserDeleteChat = $CurrentState.AllowUserDeleteChat }
    if ($null -eq $Settings.ReadReceiptsEnabledType) { $Settings.ReadReceiptsEnabledType = $CurrentState.ReadReceiptsEnabledType }
    if ($null -eq $Settings.CreateCustomEmojis) { $Settings.CreateCustomEmojis = $CurrentState.CreateCustomEmojis }
    if ($null -eq $Settings.DeleteCustomEmojis) { $Settings.DeleteCustomEmojis = $CurrentState.DeleteCustomEmojis }
    if ($null -eq $Settings.AllowSecurityEndUserReporting) { $Settings.AllowSecurityEndUserReporting = $CurrentState.AllowSecurityEndUserReporting }
    if ($null -eq $Settings.AllowCommunicationComplianceEndUserReporting) { $Settings.AllowCommunicationComplianceEndUserReporting = $CurrentState.AllowCommunicationComplianceEndUserReporting }

    $StateIsCorrect =   ($CurrentState.AllowOwnerDeleteMessage -eq $Settings.AllowOwnerDeleteMessage) -and
                        ($CurrentState.AllowUserDeleteMessage -eq $Settings.AllowUserDeleteMessage) -and
                        ($CurrentState.AllowUserEditMessage -eq $Settings.AllowUserEditMessage) -and
                        ($CurrentState.AllowUserDeleteChat -eq $Settings.AllowUserDeleteChat) -and
                        ($CurrentState.ReadReceiptsEnabledType -eq $Settings.ReadReceiptsEnabledType) -and
                        ($CurrentState.CreateCustomEmojis -eq $Settings.CreateCustomEmojis) -and
                        ($CurrentState.DeleteCustomEmojis -eq $Settings.DeleteCustomEmojis) -and
                        ($CurrentState.AllowSecurityEndUserReporting -eq $Settings.AllowSecurityEndUserReporting) -and
                        ($CurrentState.AllowCommunicationComplianceEndUserReporting -eq $Settings.AllowCommunicationComplianceEndUserReporting)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Teams Messaging policy already configured.' -sev Info
        } else {
            $cmdparams = @{
                Identity = 'Global'
                AllowOwnerDeleteMessage = $Settings.AllowOwnerDeleteMessage
                AllowUserDeleteMessage = $Settings.AllowUserDeleteMessage
                AllowUserEditMessage = $Settings.AllowUserEditMessage
                AllowUserDeleteChat = $Settings.AllowUserDeleteChat
                ReadReceiptsEnabledType = $Settings.ReadReceiptsEnabledType
                CreateCustomEmojis = $Settings.CreateCustomEmojis
                DeleteCustomEmojis = $Settings.DeleteCustomEmojis
                AllowSecurityEndUserReporting = $Settings.AllowSecurityEndUserReporting
                AllowCommunicationComplianceEndUserReporting = $Settings.AllowCommunicationComplianceEndUserReporting
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMessagingPolicy' -CmdParams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated global Teams messaging policy' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to configure global Teams messaging policy." -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Teams messaging policy is configured correctly.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Teams messaging policy is not configured correctly.' -sev Alert
        }
    }

    if ($Setings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsMessagingPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}

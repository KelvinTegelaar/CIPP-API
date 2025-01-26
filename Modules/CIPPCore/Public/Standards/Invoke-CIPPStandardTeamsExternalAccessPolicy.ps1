Function Invoke-CIPPStandardTeamsExternalAccessPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsExternalAccessPolicy
    .SYNOPSIS
        (Label) External Access Settings for Microsoft Teams
    .DESCRIPTION
        (Helptext) Sets the properties of the Global external access policy.
        (DocsDescription) Sets the properties of the Global external access policy. External access policies determine whether or not your users can: 1) communicate with users who have Session Initiation Protocol (SIP) accounts with a federated organization; 2) communicate with users who are using custom applications built with Azure Communication Services; 3) access Skype for Business Server over the Internet, without having to log on to your internal network; 4) communicate with users who have SIP accounts with a public instant messaging (IM) provider such as Skype; and, 5) communicate with people who are using Teams with an account that's not managed by an organization.
    .NOTES
        CAT
            Teams Standards
        TAG
            "mediumimpact"
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsExternalAccessPolicy.EnableFederationAccess","label":"Allow communication from trusted organizations"}
            {"type":"switch","name":"standards.TeamsExternalAccessPolicy.EnablePublicCloudAccess","label":"Allow user to communicate with Skype users"}
            {"type":"switch","name":"standards.TeamsExternalAccessPolicy.EnableTeamsConsumerAccess","label":"Allow communication with unmanaged Teams accounts"}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-CsExternalAccessPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/teams-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsExternalAccessPolicy'

    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsExternalAccessPolicy' -CmdParams @{Identity = 'Global' }
    | Select-Object *

    if ($null -eq $Settings.EnableFederationAccess) { $Settings.EnableFederationAccess = $false }
    if ($null -eq $Settings.EnablePublicCloudAccess) { $Settings.EnablePublicCloudAccess = $false }
    if ($null -eq $Settings.EnableTeamsConsumerAccess) { $Settings.EnableTeamsConsumerAccess = $false }

    $StateIsCorrect = ($CurrentState.EnableFederationAccess -eq $Settings.EnableFederationAccess) -and
                        ($CurrentState.EnablePublicCloudAccess -eq $Settings.EnablePublicCloudAccess) -and
                        ($CurrentState.EnableTeamsConsumerAccess -eq $Settings.EnableTeamsConsumerAccess)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'External Access Policy already set.' -sev Info
        } else {
            $cmdparams = @{
                Identity                  = 'Global'
                EnableFederationAccess    = $Settings.EnableFederationAccess
                EnablePublicCloudAccess   = $Settings.EnablePublicCloudAccess
                EnableTeamsConsumerAccess = $Settings.EnableTeamsConsumerAccess
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsExternalAccessPolicy' -CmdParams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated External Access Policy' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set External Access Policy. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'External Access Policy is set correctly.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'External Access Policy is not set correctly.' -sev Alert
        }
    }

    if ($Setings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsExternalAccessPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}

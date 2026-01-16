function Invoke-CIPPStandardTeamsExternalAccessPolicy {
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
        EXECUTIVETEXT
            Defines the organization's policy for communicating with external users through Teams, including other organizations, Skype users, and unmanaged accounts. This fundamental setting determines the scope of external collaboration while maintaining security boundaries for business communications.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsExternalAccessPolicy.EnableFederationAccess","label":"Allow communication from trusted organizations"}
            {"type":"switch","name":"standards.TeamsExternalAccessPolicy.EnableTeamsConsumerAccess","label":"Allow communication with unmanaged Teams accounts"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-30
        POWERSHELLEQUIVALENT
            Set-CsExternalAccessPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsExternalAccessPolicy' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsExternalAccessPolicy' -CmdParams @{Identity = 'Global' } |
            Select-Object *
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsExternalAccessPolicy state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $EnableFederationAccess = $Settings.EnableFederationAccess ?? $false
    $EnableTeamsConsumerAccess = $Settings.EnableTeamsConsumerAccess ?? $false

    $StateIsCorrect = ($CurrentState.EnableFederationAccess -eq $EnableFederationAccess) -and
    ($CurrentState.EnableTeamsConsumerAccess -eq $EnableTeamsConsumerAccess)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'External Access Policy already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity                  = 'Global'
                EnableFederationAccess    = $EnableFederationAccess
                EnableTeamsConsumerAccess = $EnableTeamsConsumerAccess
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsExternalAccessPolicy' -CmdParams $cmdParams
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
            Write-StandardsAlert -message 'External Access Policy is not set correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsExternalAccessPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'External Access Policy is not set correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsExternalAccessPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

        $CurrentValue = @{
            EnableFederationAccess    = $CurrentState.EnableFederationAccess
            EnableTeamsConsumerAccess = $CurrentState.EnableTeamsConsumerAccess
        }
        $ExpectedValue = @{
            EnableFederationAccess    = $EnableFederationAccess
            EnableTeamsConsumerAccess = $EnableTeamsConsumerAccess
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsExternalAccessPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}

Function Invoke-CIPPStandardTeamsFederationConfiguration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsFederationConfiguration
    .SYNOPSIS
        (Label) Federation Configuration for Microsoft Teams
    .DESCRIPTION
        (Helptext) Sets the properties of the Global federation configuration.
        (DocsDescription) Sets the properties of the Global federation configuration. Federation configuration settings determine whether or not your users can communicate with users who have SIP accounts with a federated organization.
    .NOTES
        CAT
            Teams Standards
        TAG
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsFederationConfiguration.AllowTeamsConsumer","label":"Allow users to communicate with other organizations"}
            {"type":"switch","name":"standards.TeamsFederationConfiguration.AllowPublicUsers","label":"Allow users to communicate with Skype Users"}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsFederationConfiguration.DomainControl","label":"Communication Mode","options":[{"label":"Allow all external domains","value":"AllowAllExternal"},{"label":"Block all external domains","value":"BlockAllExternal"},{"label":"Allow specific external domains","value":"AllowSpecificExternal"},{"label":"Block specific external domains","value":"BlockSpecificExternal"}]}
            {"type":"textField","name":"standards.TeamsFederationConfiguration.DomainList","label":"Domains, Comma separated","required":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-31
        POWERSHELLEQUIVALENT
            Set-CsTenantFederationConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/teams-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsFederationConfiguration'

    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTenantFederationConfiguration' -CmdParams @{Identity = 'Global' }
    | Select-Object *

    $DomainControl = $Settings.DomainControl.value ?? $Settings.DomainControl
    Switch ($DomainControl) {
        'AllowAllExternal' {
            $AllowFederatedUsers = $true
            $AllowedDomainsAsAList = 'AllowAllKnownDomains'
            $BlockedDomains = @()
        }
        'BlockAllExternal' {
            $AllowFederatedUsers = $false
            $AllowedDomainsAsAList = 'AllowAllKnownDomains'
            $BlockedDomains = @()
        }
        'AllowSpecificExternal' {
            $AllowFederatedUsers = $true
            $BlockedDomains = @()
            if ($null -ne $Settings.DomainList) {
                $AllowedDomainsAsAList = @($Settings.DomainList).Split(',').Trim()
            } else {
                $AllowedDomainsAsAList = @()
            }
        }
        'BlockSpecificExternal' {
            $AllowFederatedUsers = $true
            $AllowedDomainsAsAList = 'AllowAllKnownDomains'
            if ($null -ne $Settings.DomainList) {
                $BlockedDomains = @($Settings.DomainList).Split(',').Trim()
            } else {
                $BlockedDomains = @()
            }
        }
        Default {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Federation Configuration: Invalid $DomainControl parameter" -sev Error
            Return
        }
    }

    # TODO : Add proper validation for the domain list
    # $CurrentState.AllowedDomains returns a PSObject System.Object and adds a Domain= for each allowed domain, ex {Domain=example.com, Domain=example2.com}

    $StateIsCorrect = ($CurrentState.AllowTeamsConsumer -eq $Settings.AllowTeamsConsumer) -and
                        ($CurrentState.AllowPublicUsers -eq $Settings.AllowPublicUsers) -and
                        ($CurrentState.AllowFederatedUsers -eq $AllowFederatedUsers) -and
                        ($CurrentState.AllowedDomains -eq $AllowedDomainsAsAList) -and
                        ($CurrentState.BlockedDomains -eq $BlockedDomains)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Federation Configuration already set.' -sev Info
        } else {
            $cmdparams = @{
                Identity              = 'Global'
                AllowTeamsConsumer    = $Settings.AllowTeamsConsumer
                AllowPublicUsers      = $Settings.AllowPublicUsers
                AllowFederatedUsers   = $AllowFederatedUsers
                AllowedDomainsAsAList = $AllowedDomainsAsAList
                BlockedDomains        = $BlockedDomains
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTenantFederationConfiguration' -CmdParams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Federation Configuration Policy' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Federation Configuration Policy. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Federation Configuration is set correctly.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Federation Configuration is not set correctly.' -sev Alert
        }
    }

    if ($Setings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'FederationConfiguration' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}

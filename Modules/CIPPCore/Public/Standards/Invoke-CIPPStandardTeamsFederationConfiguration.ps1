function Invoke-CIPPStandardTeamsFederationConfiguration {
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsFederationConfiguration'

    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTenantFederationConfiguration' -CmdParams @{Identity = 'Global' } | Select-Object *

    $AllowAllKnownDomains = New-CsEdgeAllowAllKnownDomains
    $DomainControl = $Settings.DomainControl.value ?? $Settings.DomainControl
    $AllowedDomainsAsAList = @()
    switch ($DomainControl) {
        'AllowAllExternal' {
            $AllowFederatedUsers = $true
            $AllowedDomains = $AllowAllKnownDomains
            $BlockedDomains = @()
        }
        'BlockAllExternal' {
            $AllowFederatedUsers = $false
            $AllowedDomains = $AllowAllKnownDomains
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
        default {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Federation Configuration: Invalid $DomainControl parameter" -sev Error
            return
        }
    }

    $CurrentAllowedDomains = $CurrentState.AllowedDomains
    if ($CurrentAllowedDomains.GetType().Name -eq 'PSObject') {
        $CurrentAllowedDomains = $CurrentAllowedDomains.Domain | Sort-Object
        $DomainList = ($CurrentAllowedDomains | Sort-Object) ?? @()
        $AllowedDomainsMatches = -not (Compare-Object -ReferenceObject $AllowedDomainsAsAList -DifferenceObject $DomainList)
    } elseif ($CurrentAllowedDomains.GetType().Name -eq 'Deserialized.Microsoft.Rtc.Management.WritableConfig.Settings.Edge.AllowAllKnownDomains') {
        $CurrentAllowedDomains = $CurrentAllowedDomains.ToString()
        $AllowedDomainsMatches = $CurrentAllowedDomains -eq $AllowedDomains.ToString()
    }

    $BlockedDomainsMatches = -not (Compare-Object -ReferenceObject $BlockedDomains -DifferenceObject $CurrentState.BlockedDomains)

    $StateIsCorrect = ($CurrentState.AllowTeamsConsumer -eq $Settings.AllowTeamsConsumer) -and
    ($CurrentState.AllowFederatedUsers -eq $AllowFederatedUsers) -and
    $AllowedDomainsMatches -and
    $BlockedDomainsMatches

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Federation Configuration already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity            = 'Global'
                AllowTeamsConsumer  = $Settings.AllowTeamsConsumer
                AllowFederatedUsers = $AllowFederatedUsers
                BlockedDomains      = $BlockedDomains
            }

            if (!$AllowedDomainsAsAList) {
                $cmdParams.AllowedDomains = $AllowedDomains
            } else {
                $cmdParams.AllowedDomainsAsAList = $AllowedDomainsAsAList
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTenantFederationConfiguration' -CmdParams $cmdParams
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
            Write-StandardsAlert -message 'Federation Configuration is not set correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsFederationConfiguration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Federation Configuration is not set correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'FederationConfiguration' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        if ($StateIsCorrect -eq $true) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState | Select-Object AllowTeamsConsumer, AllowFederatedUsers, AllowedDomains, BlockedDomains
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsFederationConfiguration' -FieldValue $FieldValue -Tenant $Tenant
    }
}

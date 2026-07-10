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
        EXECUTIVETEXT
            Configures how the organization federates with external organizations for Teams communication, controlling whether employees can communicate with specific external domains or all external organizations. This setting enables secure inter-organizational collaboration while maintaining control over external communications.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsFederationConfiguration.AllowTeamsConsumer","label":"Allow users to communicate with other organizations"}
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.TeamsFederationConfiguration.DomainControl","label":"Communication Mode","options":[{"label":"Allow all external domains","value":"AllowAllExternal"},{"label":"Block all external domains","value":"BlockAllExternal"},{"label":"Allow specific external domains","value":"AllowSpecificExternal"},{"label":"Block specific external domains","value":"BlockSpecificExternal"}]}
            {"type":"textField","name":"standards.TeamsFederationConfiguration.DomainList","label":"Domains, Comma separated","required":false,"condition":{"field":"standards.TeamsFederationConfiguration.DomainControl.value","compareType":"isOneOf","compareValue":["AllowSpecificExternal","BlockSpecificExternal"]}}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-31
        POWERSHELLEQUIVALENT
            Set-CsTenantFederationConfiguration
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "MCOSTANDARD"
            "MCOEV"
            "MCOIMP"
            "TEAMS1"
            "Teams_Room_Standard"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsFederationConfiguration' -TenantFilter $Tenant -Preset Teams

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TenantFederationConfiguration' -Action Get -Identity 'Global'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsFederationConfiguration state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # ConfigAPI (TenantFederationSettings) domain payload shapes:
    #   Allow all external      -> AllowedDomains = @()                       (empty array)
    #   Allow specific external -> AllowedDomains = @{ AllowList = @(list) }
    #   Block specific external -> AllowedDomains = @{ AllowList = @() } + BlockedDomains = @(list)
    $DomainControl = $Settings.DomainControl.value ?? $Settings.DomainControl
    $AllowedDomainsAsAList = @()
    $BlockedDomains = @()
    switch ($DomainControl) {
        'AllowAllExternal' {
            $AllowFederatedUsers = $true
            $AllowedDomainsPayload = @()
            $ExpectedAllowAllKnown = $true
        }
        'BlockAllExternal' {
            $AllowFederatedUsers = $false
            $AllowedDomainsPayload = @()
            $ExpectedAllowAllKnown = $true
        }
        'AllowSpecificExternal' {
            $AllowFederatedUsers = $true
            if ($null -ne $Settings.DomainList) {
                $AllowedDomainsAsAList = @($Settings.DomainList).Split(',').Trim() | Sort-Object
            }
            $AllowedDomainsPayload = @{ AllowList = @($AllowedDomainsAsAList) }
            $ExpectedAllowAllKnown = $false
        }
        'BlockSpecificExternal' {
            $AllowFederatedUsers = $true
            if ($null -ne $Settings.DomainList) {
                $BlockedDomains = @($Settings.DomainList).Split(',').Trim() | Sort-Object
            }
            $AllowedDomainsPayload = @{ AllowList = @() }
            $ExpectedAllowAllKnown = $true
        }
        default {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Federation Configuration: Invalid $DomainControl parameter" -sev Error
            return
        }
    }

    # Parse current state (ConfigAPI TenantFederationSettings GET shape). NOTE the GET/PUT
    # asymmetry: the GET nests the allow-list under AllowedDomains.AllowedDomain (allow-all =
    # {} with no AllowedDomain), whereas the PUT expects AllowedDomains.AllowList / []. Items
    # may be plain strings or objects with a .Domain property, so handle both.
    $CurrentAllowedDomains = @()
    $ad = $CurrentState.AllowedDomains
    if ($ad -and ($ad.PSObject.Properties.Name -contains 'AllowedDomain') -and $ad.AllowedDomain) {
        $CurrentAllowedDomains = @($ad.AllowedDomain | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.Domain) { $_.Domain } else { "$_" } }) | Sort-Object
    }
    # Allow-all-known = no explicit allow-list present (ConfigAPI returns {} for allow-all).
    $IsCurrentAllowAllKnownDomains = ($CurrentAllowedDomains.Count -eq 0)
    $CurrentBlockedDomains = @()
    if ($CurrentState.BlockedDomains) {
        $CurrentBlockedDomains = @($CurrentState.BlockedDomains | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.Domain) { $_.Domain } else { "$_" } }) | Sort-Object
    }
    $AllowedDomainsMatches = $false
    $BlockedDomainsMatches = $false

    # Mode-specific validation
    switch ($DomainControl) {
        'AllowAllExternal' {
            $AllowedDomainsMatches = $IsCurrentAllowAllKnownDomains
            $BlockedDomainsMatches = (!$CurrentBlockedDomains -or @($CurrentBlockedDomains).Count -eq 0)
        }
        'BlockAllExternal' {
            # When blocking all, federation must be disabled
            $AllowedDomainsMatches = $true
            $BlockedDomainsMatches = $true
        }
        'AllowSpecificExternal' {
            $AllowedDomainsMatches = -not (Compare-Object -ReferenceObject $AllowedDomainsAsAList -DifferenceObject $CurrentAllowedDomains)
            $BlockedDomainsMatches = (!$CurrentBlockedDomains -or @($CurrentBlockedDomains).Count -eq 0)
        }
        'BlockSpecificExternal' {
            # Allowed should be AllowAllKnownDomains, blocked domains already parsed above
            $AllowedDomainsMatches = $IsCurrentAllowAllKnownDomains
            $BlockedDomainsMatches = -not (Compare-Object -ReferenceObject $BlockedDomains -DifferenceObject $CurrentBlockedDomains)
        }
    }

    $ExpectedBlockedDomains = $BlockedDomains ?? @()

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
                AllowedDomains      = $AllowedDomainsPayload
                BlockedDomains      = @($BlockedDomains)
            }

            try {
                # -NoRead: send bare props exactly like ACMS (no Key envelope) for the federation write
                $null = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TenantFederationConfiguration' -Action Set -Parameters $cmdParams -NoRead
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

        $CurrentAllowedDomainsForReport = if ($IsCurrentAllowAllKnownDomains) {
            'AllowAllKnownDomains'
        } elseif ($CurrentAllowedDomains) {
            $CurrentAllowedDomains
        } else {
            @()
        }

        # Normalize expected allowed domains for reporting
        $ExpectedAllowedDomainsForReport = if ($AllowedDomainsAsAList -and $AllowedDomainsAsAList.Count -gt 0) {
            $AllowedDomainsAsAList
        } elseif ($ExpectedAllowAllKnown) {
            'AllowAllKnownDomains'
        } else {
            @()
        }

        # Normalize blocked domains for reporting
        $CurrentBlockedDomainsForReport = if ($null -ne $CurrentBlockedDomains -and @($CurrentBlockedDomains).Count -gt 0) {
            @($CurrentBlockedDomains)
        } else {
            @()
        }

        $ExpectedBlockedDomainsForReport = if ($null -ne $ExpectedBlockedDomains -and @($ExpectedBlockedDomains).Count -gt 0) {
            @($ExpectedBlockedDomains)
        } else {
            @()
        }

        $CurrentValue = @{
            AllowTeamsConsumer  = $CurrentState.AllowTeamsConsumer
            AllowFederatedUsers = $CurrentState.AllowFederatedUsers
            AllowedDomains      = $CurrentAllowedDomainsForReport
            BlockedDomains      = $CurrentBlockedDomainsForReport
        }
        $ExpectedValue = @{
            AllowTeamsConsumer  = $Settings.AllowTeamsConsumer
            AllowFederatedUsers = $AllowFederatedUsers
            AllowedDomains      = $ExpectedAllowedDomainsForReport
            BlockedDomains      = $ExpectedBlockedDomainsForReport
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsFederationConfiguration' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}

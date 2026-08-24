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
            {"type":"switch","name":"standards.TeamsFederationConfiguration.AllowTeamsConsumerInbound","label":"Allow unmanaged Teams users to initiate contact","condition":{"field":"standards.TeamsFederationConfiguration.AllowTeamsConsumer","compareType":"is","compareValue":true}}
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

    # ConfigAPI (TenantFederationSettings) domain payload shapes are GET-symmetric:
    #   Allow all external      -> AllowedDomains = @{}                       (empty OBJECT = AllowAllKnownDomains)
    #   Allow specific external -> AllowedDomains = @{ AllowedDomain = @(@{ Domain = 'x' }) }
    #   Block specific external -> AllowedDomains = @{} + BlockedDomains = @(@{ Domain = 'x' })
    # NEVER send an empty ARRAY (or an AllowList envelope) for AllowedDomains: the ConfigAPI
    # coerces it into an explicit EMPTY allow list ({"AllowedDomain":[]}) - federation with
    # nobody - while the write reports success and the next read looks aligned. That flipped
    # whole fleets to "Block all external domains" (CyberDrain/CIPP#364).
    $DomainControl = $Settings.DomainControl.value ?? $Settings.DomainControl
    # An untoggled switch is absent from the settings; default it to $false so we never send null to the ConfigApi
    $AllowTeamsConsumer = $Settings.AllowTeamsConsumer ?? $false
    $AllowTeamsConsumerInbound = $Settings.AllowTeamsConsumerInbound ?? $false
    $AllowedDomainsAsAList = @()
    $BlockedDomains = @()
    switch ($DomainControl) {
        'AllowAllExternal' {
            $AllowFederatedUsers = $true
            $AllowedDomainsPayload = @{}
            $ExpectedAllowAllKnown = $true
        }
        'BlockAllExternal' {
            $AllowFederatedUsers = $false
            $AllowedDomainsPayload = @{}
            $ExpectedAllowAllKnown = $true
        }
        'AllowSpecificExternal' {
            $AllowFederatedUsers = $true
            if ($null -ne $Settings.DomainList) {
                $AllowedDomainsAsAList = @($Settings.DomainList).Split(',').Trim() | Sort-Object
            }
            $AllowedDomainsPayload = @{ AllowedDomain = @($AllowedDomainsAsAList | ForEach-Object { @{ Domain = $_ } }) }
            $ExpectedAllowAllKnown = $false
        }
        'BlockSpecificExternal' {
            $AllowFederatedUsers = $true
            if ($null -ne $Settings.DomainList) {
                $BlockedDomains = @($Settings.DomainList).Split(',').Trim() | Sort-Object
            }
            $AllowedDomainsPayload = @{}
            $ExpectedAllowAllKnown = $true
        }
        default {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Federation Configuration: Invalid $DomainControl parameter" -sev Error
            return
        }
    }

    # Parse current state (ConfigAPI TenantFederationSettings GET shape): allow-all reads as
    # AllowedDomains = {} with NO AllowedDomain member; an explicit allow list nests items
    # (plain strings or {Domain} objects) under AllowedDomains.AllowedDomain. An allow list
    # that is PRESENT but EMPTY ({"AllowedDomain":[]}) is NOT allow-all - it federates with
    # nobody (the #364 breakage state) - so key off the member's presence, not the item count,
    # or broken tenants read as compliant forever.
    $CurrentAllowedDomains = @()
    $ad = $CurrentState.AllowedDomains
    $HasExplicitAllowList = [bool]($ad -and ($ad.PSObject.Properties.Name -contains 'AllowedDomain'))
    if ($HasExplicitAllowList -and $ad.AllowedDomain) {
        $CurrentAllowedDomains = @($ad.AllowedDomain | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.Domain) { $_.Domain } else { "$_" } }) | Sort-Object
    }
    $IsCurrentAllowAllKnownDomains = -not $HasExplicitAllowList
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
            # Both lists are already Sort-Object'd; compare as joined strings. Avoids Compare-Object,
            # whose parameter binder coerces an empty array @() to $null and then throws.
            $AllowedDomainsMatches = (@($AllowedDomainsAsAList) -join ',') -eq (@($CurrentAllowedDomains) -join ',')
            $BlockedDomainsMatches = (!$CurrentBlockedDomains -or @($CurrentBlockedDomains).Count -eq 0)
        }
        'BlockSpecificExternal' {
            # Allowed should be AllowAllKnownDomains, blocked domains already parsed above
            $AllowedDomainsMatches = $IsCurrentAllowAllKnownDomains
            $BlockedDomainsMatches = (@($BlockedDomains) -join ',') -eq (@($CurrentBlockedDomains) -join ',')
        }
    }

    $ExpectedBlockedDomains = $BlockedDomains ?? @()

    $StateIsCorrect = ($CurrentState.AllowTeamsConsumer -eq $AllowTeamsConsumer) -and
    ($CurrentState.AllowTeamsConsumerInbound -eq $AllowTeamsConsumerInbound) -and
    ($CurrentState.AllowFederatedUsers -eq $AllowFederatedUsers) -and
    $AllowedDomainsMatches -and
    $BlockedDomainsMatches

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Federation Configuration already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity                  = 'Global'
                AllowTeamsConsumer        = $AllowTeamsConsumer
                AllowTeamsConsumerInbound = $AllowTeamsConsumerInbound
                AllowFederatedUsers       = $AllowFederatedUsers
                AllowedDomains            = $AllowedDomainsPayload
                BlockedDomains            = @($BlockedDomains | ForEach-Object { @{ Domain = $_ } })
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
            AllowTeamsConsumer         = $CurrentState.AllowTeamsConsumer
            AllowTeamsConsumerInbound = $CurrentState.AllowTeamsConsumerInbound
            AllowFederatedUsers       = $CurrentState.AllowFederatedUsers
            AllowedDomains      = $CurrentAllowedDomainsForReport
            BlockedDomains      = $CurrentBlockedDomainsForReport
        }
        $ExpectedValue = @{
            AllowTeamsConsumer         = $AllowTeamsConsumer
            AllowTeamsConsumerInbound = $AllowTeamsConsumerInbound
            AllowFederatedUsers       = $AllowFederatedUsers
            AllowedDomains            = $ExpectedAllowedDomainsForReport
            BlockedDomains      = $ExpectedBlockedDomainsForReport
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsFederationConfiguration' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}

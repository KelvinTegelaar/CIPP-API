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
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsFederationConfiguration' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTenantFederationConfiguration' -CmdParams @{Identity = 'Global' } |
            Select-Object *
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsFederationConfiguration state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $AllowAllKnownDomains = New-CsEdgeAllowAllKnownDomains
    $DomainControl = $Settings.DomainControl.value ?? $Settings.DomainControl
    $AllowedDomainsAsAList = @()
    switch ($DomainControl) {
        'AllowAllExternal' {
            $AllowFederatedUsers = $true
            $AllowedDomains = $AllowAllKnownDomains
            $AllowedDomainsAsAList = @()
            $BlockedDomains = @()
        }
        'BlockAllExternal' {
            $AllowFederatedUsers = $false
            $AllowedDomains = $AllowAllKnownDomains
            $AllowedDomainsAsAList = @()
            $BlockedDomains = @()
        }
        'AllowSpecificExternal' {
            $AllowFederatedUsers = $true
            $AllowedDomains = $null
            $BlockedDomains = @()
            if ($null -ne $Settings.DomainList) {
                $AllowedDomainsAsAList = @($Settings.DomainList).Split(',').Trim()
            } else {
                $AllowedDomainsAsAList = @()
            }
        }
        'BlockSpecificExternal' {
            $AllowFederatedUsers = $true
            $AllowedDomains = $AllowAllKnownDomains
            $AllowedDomainsAsAList = @()
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

    # Parse current allowed domains and compare with expected configuration
    $CurrentAllowedDomains = $CurrentState.AllowedDomains
    $AllowedDomainsMatches = $false
    $IsCurrentAllowAllKnownDomains = $false

    if (!$CurrentAllowedDomains) {
        # Current state has no allowed domains set
        $CurrentAllowedDomains = @()
        $AllowedDomainsMatches = (!$AllowedDomains -and $AllowedDomainsAsAList.Count -eq 0)
    } elseif ($CurrentAllowedDomains.GetType().Name -eq 'PSObject') {
        # Current state is a PSObject - check if it has AllowAllKnownDomains, AllowedDomain, or Domain property
        $properties = Get-Member -InputObject $CurrentAllowedDomains -MemberType Properties, NoteProperty

        if ($null -ne $CurrentAllowedDomains.AllowAllKnownDomains -or (Get-Member -InputObject $CurrentAllowedDomains -Name 'AllowAllKnownDomains')) {
            # PSObject with AllowAllKnownDomains property = Allow all known domains
            $IsCurrentAllowAllKnownDomains = $true
            $CurrentAllowedDomains = 'AllowAllKnownDomains'
            Write-Information 'Detected AllowAllKnownDomains configuration (via property)'
            $AllowedDomainsMatches = ($null -ne $AllowedDomains) -and (!$AllowedDomainsAsAList -or $AllowedDomainsAsAList.Count -eq 0)
        } elseif ($null -ne $CurrentAllowedDomains.AllowedDomain -or (Get-Member -InputObject $CurrentAllowedDomains -Name 'AllowedDomain')) {
            # PSObject with AllowedDomain property = Specific domain list (array of objects with Domain property)
            $CurrentAllowedDomains = @($CurrentAllowedDomains.AllowedDomain | ForEach-Object { $_.Domain }) | Sort-Object
            $DomainList = ($CurrentAllowedDomains | Sort-Object) ?? @()
            Write-Information "Detected AllowedDomain list: $($CurrentAllowedDomains -join ', ')"
            # Compare with expected domain list
            if ($AllowedDomainsAsAList -and $AllowedDomainsAsAList.Count -gt 0) {
                $AllowedDomainsMatches = -not (Compare-Object -ReferenceObject $AllowedDomainsAsAList -DifferenceObject $DomainList)
            } else {
                $AllowedDomainsMatches = $false
            }
        } elseif ($null -ne $CurrentAllowedDomains.Domain -or (Get-Member -InputObject $CurrentAllowedDomains -Name 'Domain')) {
            # PSObject with Domain property = Specific domain list (direct array)
            $CurrentAllowedDomains = $CurrentAllowedDomains.Domain | Sort-Object
            $DomainList = ($CurrentAllowedDomains | Sort-Object) ?? @()
            # Compare with expected domain list
            if ($AllowedDomainsAsAList -and $AllowedDomainsAsAList.Count -gt 0) {
                $AllowedDomainsMatches = -not (Compare-Object -ReferenceObject $AllowedDomainsAsAList -DifferenceObject $DomainList)
            } else {
                $AllowedDomainsMatches = $false
            }
        } elseif (!$properties -or $properties.Count -eq 0) {
            # Empty PSObject with no properties = AllowAllKnownDomains (this is how Teams API returns it)
            $IsCurrentAllowAllKnownDomains = $true
            $CurrentAllowedDomains = 'AllowAllKnownDomains'
            Write-Information 'Detected AllowAllKnownDomains configuration (empty PSObject)'
            $AllowedDomainsMatches = ($null -ne $AllowedDomains) -and (!$AllowedDomainsAsAList -or $AllowedDomainsAsAList.Count -eq 0)
        } else {
            # Unknown PSObject structure
            Write-Information "Unknown PSObject structure with properties: $($properties.Name -join ', ')"
            $CurrentAllowedDomains = @()
            $AllowedDomainsMatches = $false
        }
    } elseif ($CurrentAllowedDomains.GetType().Name -eq 'Deserialized.Microsoft.Rtc.Management.WritableConfig.Settings.Edge.AllowAllKnownDomains') {
        # Current state is set to AllowAllKnownDomains
        $IsCurrentAllowAllKnownDomains = $true
        # Match if expected is also AllowAllKnownDomains (not a specific list)
        $AllowedDomainsMatches = ($null -ne $AllowedDomains) -and (!$AllowedDomainsAsAList -or $AllowedDomainsAsAList.Count -eq 0)
    }

    # Normalize blocked domains for comparison
    $CurrentBlockedDomains = $CurrentState.BlockedDomains ?? @()
    $ExpectedBlockedDomains = $BlockedDomains ?? @()
    $BlockedDomainsMatches = -not (Compare-Object -ReferenceObject $ExpectedBlockedDomains -DifferenceObject $CurrentBlockedDomains)

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

            if ($AllowedDomainsAsAList -and $AllowedDomainsAsAList.Count -gt 0) {
                $cmdParams.AllowedDomainsAsAList = $AllowedDomainsAsAList
            } else {
                $cmdParams.AllowedDomains = $AllowedDomains
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTenantFederationConfiguration' -CmdParams $cmdParams
                Write-Information "Updated Teams Federation Configuration for tenant $Tenant with parameters: $($cmdParams | ConvertTo-Json -Compress -Depth 5)"

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
        } elseif ($AllowedDomains) {
            'AllowAllKnownDomains'
        } else {
            @()
        }

        $CurrentValue = @{
            AllowTeamsConsumer  = $CurrentState.AllowTeamsConsumer
            AllowFederatedUsers = $CurrentState.AllowFederatedUsers
            AllowedDomains      = $CurrentAllowedDomainsForReport
            BlockedDomains      = $CurrentBlockedDomains
        }
        $ExpectedValue = @{
            AllowTeamsConsumer  = $Settings.AllowTeamsConsumer
            AllowFederatedUsers = $AllowFederatedUsers
            AllowedDomains      = $ExpectedAllowedDomainsForReport
            BlockedDomains      = $ExpectedBlockedDomains
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsFederationConfiguration' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}

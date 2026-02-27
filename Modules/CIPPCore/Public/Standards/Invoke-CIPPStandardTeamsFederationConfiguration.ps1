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

    # Parse current state based on DomainControl mode
    $CurrentAllowedDomains = $CurrentState.AllowedDomains
    $CurrentBlockedDomains = $CurrentState.BlockedDomains
    $IsCurrentAllowAllKnownDomains = $false
    $AllowedDomainsMatches = $false
    $BlockedDomainsMatches = $false

    # Check if current allowed domains is AllowAllKnownDomains, and parse specific domains if not
    if ($CurrentAllowedDomains) {
        if ($CurrentAllowedDomains.GetType().Name -eq 'PSObject') {
            $properties = Get-Member -InputObject $CurrentAllowedDomains -MemberType Properties, NoteProperty
            if (($null -ne $CurrentAllowedDomains.AllowAllKnownDomains) -or
                (Get-Member -InputObject $CurrentAllowedDomains -Name 'AllowAllKnownDomains') -or
                (!$properties -or $properties.Count -eq 0)) {
                $IsCurrentAllowAllKnownDomains = $true
                Write-Information "Current AllowedDomains is AllowAllKnownDomains"
            } else {
                # Parse specific allowed domains list
                if ($null -ne $CurrentAllowedDomains.AllowedDomain -or (Get-Member -InputObject $CurrentAllowedDomains -Name 'AllowedDomain')) {
                    $CurrentAllowedDomains = @($CurrentAllowedDomains.AllowedDomain | ForEach-Object { $_.Domain }) | Sort-Object
                    Write-Information "Current AllowedDomains (extracted): $($CurrentAllowedDomains -join ', ')"
                } elseif ($null -ne $CurrentAllowedDomains.Domain -or (Get-Member -InputObject $CurrentAllowedDomains -Name 'Domain')) {
                    $CurrentAllowedDomains = @($CurrentAllowedDomains.Domain) | Sort-Object
                    Write-Information "Current AllowedDomains (via Domain property): $($CurrentAllowedDomains -join ', ')"
                } else {
                    $CurrentAllowedDomains = @()
                }
            }
        } elseif ($CurrentAllowedDomains.GetType().Name -eq 'Deserialized.Microsoft.Rtc.Management.WritableConfig.Settings.Edge.AllowAllKnownDomains') {
            $IsCurrentAllowAllKnownDomains = $true
            Write-Information "Current AllowedDomains is AllowAllKnownDomains (Deserialized type)"
        }
    } else {
        $CurrentAllowedDomains = @()
    }

    # Parse blocked domains upfront (always extract Domain property if present)
    if ($CurrentBlockedDomains -is [System.Collections.IEnumerable] -and $CurrentBlockedDomains -isnot [string]) {
        $blockedDomainsArray = @($CurrentBlockedDomains)
        if ($blockedDomainsArray.Count -gt 0) {
            $firstElement = $blockedDomainsArray[0]
            $hasDomainProperty = ($null -ne $firstElement.Domain) -or (Get-Member -InputObject $firstElement -Name 'Domain' -MemberType Properties, NoteProperty)

            if ($hasDomainProperty) {
                $CurrentBlockedDomains = @($blockedDomainsArray | ForEach-Object { $_.Domain }) | Sort-Object
                Write-Information "Current BlockedDomains (extracted): $($CurrentBlockedDomains -join ', ')"
            } else {
                $CurrentBlockedDomains = @($blockedDomainsArray) | Sort-Object
                Write-Information "Current BlockedDomains (plain strings): $($CurrentBlockedDomains -join ', ')"
            }
        } else {
            $CurrentBlockedDomains = @()
        }
    } else {
        $CurrentBlockedDomains = @()
    }

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
                BlockedDomains      = $BlockedDomains
            }

            if ($AllowedDomainsAsAList -and $AllowedDomainsAsAList.Count -gt 0) {
                $cmdParams.AllowedDomainsAsAList = $AllowedDomainsAsAList
            } else {
                $cmdParams.AllowedDomains = $AllowedDomains
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

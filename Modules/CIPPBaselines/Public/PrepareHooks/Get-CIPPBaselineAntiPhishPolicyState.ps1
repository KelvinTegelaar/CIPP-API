function Get-CIPPBaselineAntiPhishPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for AntiPhishPolicy: the policy and the rule that scopes it.
    .DESCRIPTION
        The graded property set depends on LICENSING, which is why this cannot be a static
        template. With Defender for Office 365 (ATP_ENTERPRISE) the classic standard grades 23
        properties including impersonation and mailbox-intelligence protection; without it,
        only the 8 that exist on a plain Exchange tenant. Grading the full set on an
        unlicensed tenant reports drift for settings that cannot be configured there.

        Note this is a per-tenant CAPABILITY check, not the standard's licence gate: the
        standard still runs on an unlicensed tenant, just against the smaller set. That is why
        requiredCapabilities carries only the Exchange group.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAntiPhishPolicies')
    if ($Policies.Count -eq 0) { return @{ Current = $null } }
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAntiPhishRules' -CollectorType 'ExoAntiPhishPolicies')
    $AcceptedDomainRows = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains')
    $AcceptedDomains = @($AcceptedDomainRows.Name | Where-Object { $_ } | Sort-Object)

    $Capabilities = $(try { Get-CIPPTenantCapabilities -TenantFilter $TenantFilter } catch { $null })
    $MDOLicensed = $Capabilities.ATP_ENTERPRISE -eq $true

    $Configured = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.name)")) { 'CIPP Default Anti-Phishing Policy' } else { "$($Item.Variables.name)" }
    $PolicyCandidates = @($Configured, 'CIPP Default Anti-Phishing Policy', 'Default Anti-Phishing Policy')
    $ExistingPolicy = @(foreach ($Candidate in $PolicyCandidates) { $Policies.Where({ "$($_.Name)" -eq $Candidate }, 'First') })[0]
    $PolicyName = if ($ExistingPolicy.Name) { "$($ExistingPolicy.Name)" } else { $Configured }

    $DesiredRuleName = "$PolicyName Rule"
    $RuleCandidates = @($DesiredRuleName, 'CIPP Default Anti-Phishing Rule', 'CIPP Default Anti-Phishing Policy')
    # A rule made in the Defender portal shares the policy's name, so the link is matched first
    $LinkedRules = $Rules.Where({ "$($_.AntiPhishPolicy)" -eq $PolicyName })
    $ExistingRule = @($LinkedRules.Where({ $RuleCandidates -contains "$($_.Name)" }); $LinkedRules; $Rules.Where({ $RuleCandidates -contains "$($_.Name)" }))[0]
    $RuleName = if ($ExistingRule.Name) { "$($ExistingRule.Name)" } else { $DesiredRuleName }

    $Policy = @($Policies.Where({ "$($_.Name)" -eq $PolicyName })) | Select-Object -First 1
    $Rule = @($Rules.Where({ "$($_.Name)" -eq $RuleName })) | Select-Object -First 1
    $V = $Item.Variables

    # Get-AntiPhishPolicy only populates Enabled for the built-in default policy; on a custom policy
    # the active state lives on the rule's State (see Invoke-ListAntiPhishingFilters). Fall back to
    # the policy value so the built-in default policy stays correct.
    $PolicyEnabled = if ($null -ne $Rule.State) { $Rule.State -eq 'Enabled' } else { [bool]$Policy.Enabled }

    $ProtectedLists = [System.Collections.Generic.List[object]]::new()
    if ($MDOLicensed) {
        $UserScope = $V.ImpersonationUserScope.value ?? $V.ImpersonationUserScope ?? 'Unmanaged'
        if ($UserScope -notin @('AllLicensed', 'Listed', 'Unmanaged')) {
            return @{ Current = $null; NoDataReason = "the impersonation user scope '$UserScope' is not recognised; choose Keep the tenant's current list, All licensed users or Only the users listed"; ConfigError = $true }
        }
        $ListedOnly = $UserScope -eq 'Listed'
        $DomainLabel = '[\p{L}\p{N}](?:[\p{L}\p{M}\p{N}-]{0,61}[\p{L}\p{M}\p{N}])?'
        $DomainPattern = "$DomainLabel(?:\.$DomainLabel)+"
        $AddressAtom = '[\p{L}\p{M}\p{N}!#$&''*+/=?^_`{|}~-]+'
        $AddressPattern = "^$AddressAtom(?:\.$AddressAtom)*@$DomainPattern$"
        $DomainOnlyPattern = "^$DomainPattern$"
        $ConfigProblems = [System.Collections.Generic.List[string]]::new()

        $RequestedUsers = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        $BareAddresses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        if ($UserScope -ne 'Unmanaged') {
            foreach ($Entry in @($V.TargetedUsersToProtect)) {
                $Raw = $Entry.value ?? $Entry
                if ($null -eq $Raw -or ($Raw -is [string] -and [string]::IsNullOrWhiteSpace($Raw))) { continue }
                $Text = "$Raw".Trim()
                $Split = $Text.LastIndexOf(';')
                $Address = $Text.Substring($Split + 1).Trim().ToLowerInvariant()
                if ($Raw -isnot [string] -or $Text -match '%[^%;\s]+%' -or $Address -notmatch $AddressPattern) {
                    $ConfigProblems.Add("the user entry '$Text' is not Display Name;address or an address")
                    continue
                }
                $Name = if ($Split -gt 0) { $Text.Substring(0, $Split).Replace(';', '').Trim() } else { '' }
                if ($Name) {
                    $RequestedUsers["$Name;$Address"] = $Address
                } else {
                    $null = $BareAddresses.Add($Address)
                }
            }
            $BareAddresses.ExceptWith($RequestedUsers.Values)
            $RequestedCount = $RequestedUsers.Count + $BareAddresses.Count
            if ($ListedOnly -and $RequestedCount -eq 0 -and $ConfigProblems.Count -eq 0) {
                $ConfigProblems.Add('Only the users listed is selected but the users list is empty; add users or choose another option')
            }
            if ($RequestedCount -gt 350) {
                $ConfigProblems.Add("the users list has $RequestedCount distinct user entries and Exchange allows 350 per policy; remove $($RequestedCount - 350)")
            }
        }

        $RequestedDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Entry in @($V.TargetedDomainsToProtect)) {
            $Raw = $Entry.value ?? $Entry
            if ($null -eq $Raw -or ($Raw -is [string] -and [string]::IsNullOrWhiteSpace($Raw))) { continue }
            $Text = "$Raw".Trim()
            if ($Raw -isnot [string] -or $Text -notmatch $DomainOnlyPattern) {
                $ConfigProblems.Add("the domain entry '$Text' is not a domain name")
                continue
            }
            $null = $RequestedDomains.Add($Text.ToLowerInvariant())
        }
        if ($RequestedDomains.Count -gt 50) {
            $ConfigProblems.Add("the custom domains list has $($RequestedDomains.Count) distinct domains and Exchange allows 50 per policy; remove $($RequestedDomains.Count - 50)")
        }

        if ($ConfigProblems.Count -gt 0) {
            return @{ Current = $null; NoDataReason = "the impersonation protection lists cannot be applied: $($ConfigProblems -join '; ')"; ConfigError = $true }
        }

        if ($UserScope -ne 'Unmanaged') {
            $AcceptedDomainSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            if (-not $ListedOnly) {
                foreach ($Row in $AcceptedDomainRows) {
                    if ($Row.DomainName) { $null = $AcceptedDomainSet.Add(([string]$Row.DomainName).Trim()) }
                }
            }
            $LiveUsers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $LiveExternal = [System.Collections.Generic.List[string]]::new()
            $LiveInternal = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
            foreach ($Entry in @($Policy.TargetedUsersToProtect)) {
                $Text = [string]$Entry
                if ([string]::IsNullOrWhiteSpace($Text)) { continue }
                $Split = $Text.LastIndexOf(';')
                $Address = $Text.Substring($Split + 1).Trim().ToLowerInvariant()
                $Name = if ($Split -gt 0) { $Text.Substring(0, $Split) } else { $Address }
                $Normalised = "$Name;$Address"
                if ($LiveUsers.Add($Normalised) -and -not $ListedOnly) {
                    $At = $Address.LastIndexOf('@')
                    if ($At -gt 0 -and $AcceptedDomainSet.Contains($Address.Substring($At + 1))) { $LiveInternal[$Normalised] = $Text } else { $LiveExternal.Add($Normalised) }
                }
            }

            $NeedsNames = $BareAddresses.Count -gt 0
            $Licensed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $CacheCounts = [ordered]@{}
            $Mailboxes = @()
            $Withheld = $null
            try {
                if (-not $ListedOnly) {
                    $Users = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'accountEnabled', 'userType', 'assignedLicenses' -ErrorAction Stop)
                    $CacheCounts['Users'] = $Users.Count
                    foreach ($User in $Users) {
                        if ($User.id -and $User.accountEnabled -eq $true -and $User.userType -eq 'Member' -and $User.assignedLicenses) { $null = $Licensed.Add([string]$User.id) }
                    }
                }
                if ($NeedsNames -or $Licensed.Count -gt 0) {
                    $Mailboxes = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Mailboxes' -CollectorArgs @{ Types = 'None' } -Fields 'recipientTypeDetails', 'AccountDisabled', 'WhenSoftDeleted', 'ExternalDirectoryObjectId', 'primarySmtpAddress', 'displayName' -ErrorAction Stop)
                    $CacheCounts['Mailboxes'] = $Mailboxes.Count
                }
            } catch {
                $Withheld = "a directory cache read failed: $($_.Exception.Message)"
            }
            $NamesByAddress = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $DesiredByAddress = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Mailbox in $Mailboxes) {
                $Eligible = -not $ListedOnly -and $Mailbox.recipientTypeDetails -eq 'UserMailbox' -and $Mailbox.AccountDisabled -ne $true -and
                    [string]::IsNullOrWhiteSpace([string]$Mailbox.WhenSoftDeleted) -and $Licensed.Contains([string]$Mailbox.ExternalDirectoryObjectId)
                if (-not $NeedsNames -and -not $Eligible) { continue }
                $Address = ([string]$Mailbox.primarySmtpAddress).Trim().ToLowerInvariant()
                $Name = ([string]$Mailbox.displayName).Replace(';', '').Trim()
                if (-not $Address -or -not $Name) { continue }
                if ($NeedsNames) { $NamesByAddress[$Address] = $Name }
                if ($Eligible) { $DesiredByAddress[$Address] = "$Name;$Address" }
            }

            if (-not $Withheld -and -not $ListedOnly -and $DesiredByAddress.Count -eq 0) {
                $Withheld = 'the Users and Mailboxes caches hold no enabled, licensed member with a user mailbox'
            } elseif (-not $Withheld -and $NeedsNames -and $Mailboxes.Count -eq 0) {
                $Withheld = 'the Mailboxes cache is empty, so the display names of the bare addresses cannot be looked up'
            }
            if ($Withheld) {
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "AntiPhishPolicy: the protected user list was left as it is and not graded because $Withheld." -Sev 'Info'
            } else {
                foreach ($Address in $BareAddresses) {
                    $Name = $NamesByAddress[$Address] ?? $Address
                    $RequestedUsers["$Name;$Address"] = $Address
                }
                foreach ($Address in $RequestedUsers.Values) { $null = $DesiredByAddress.Remove($Address) }
                $Preserved = [System.Collections.Generic.List[string]]::new()
                foreach ($Entry in $LiveExternal) {
                    $Address = $Entry.Substring($Entry.LastIndexOf(';') + 1)
                    if (-not $RequestedUsers.ContainsKey($Entry) -and -not [System.StringComparer]::Ordinal.Equals($DesiredByAddress[$Address], $Entry)) { $Preserved.Add($Entry) }
                }
                $DesiredCount = $DesiredByAddress.Count + $RequestedUsers.Count + $Preserved.Count
                if ($DesiredCount -gt 350) {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "AntiPhishPolicy: all licensed users, the listed users and the external entries already in the policy come to $DesiredCount and Exchange allows 350 per policy. The protected user list was left as it is and not graded; choose Only the users listed with up to 350 users to manage it." -Sev 'Warning'
                } else {
                    $Desired = [System.Collections.Generic.List[string]]::new($DesiredByAddress.Values)
                    $Desired.AddRange($RequestedUsers.Keys)
                    $Desired.AddRange($Preserved)
                    $ProtectedLists.Add([PSCustomObject]@{
                            Key = 'targetedUsersToProtect'; Param = 'TargetedUsersToProtect'
                            Label = $(if ($ListedOnly) { 'Listed users' } else { 'All licensed users' })
                            Desired = $Desired; Live = $LiveUsers; CacheCounts = $CacheCounts
                            Internal = $LiveInternal; Delta = -not $ListedOnly -and [bool]$Policy
                        })
                }
            }
        }

        if ($RequestedDomains.Count -gt 0) {
            $LiveDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Entry in @($Policy.TargetedDomainsToProtect)) {
                if (-not [string]::IsNullOrWhiteSpace("$Entry")) { $null = $LiveDomains.Add("$Entry".Trim()) }
            }
            $ProtectedLists.Add([PSCustomObject]@{
                    Key = 'targetedDomainsToProtect'; Param = 'TargetedDomainsToProtect'; Label = 'Listed domains'
                    Desired = [System.Collections.Generic.List[string]]::new($RequestedDomains); Live = $LiveDomains; CacheCounts = @{}
                })
        }
    }

    # The eight properties every tenant has.
    $Expected = [PSCustomObject]@{
        name                         = $PolicyName
        enabled                      = $true
        enableSpoofIntelligence      = $true
        enableFirstContactSafetyTips = [bool]($V.EnableFirstContactSafetyTips -eq $true)
        enableUnauthenticatedSender  = $true
        enableViaTag                 = $true
        authenticationFailAction     = "$($V.AuthenticationFailAction)"
        spoofQuarantineTag           = "$($V.SpoofQuarantineTag)"
    }
    $Current = [PSCustomObject]@{
        name                         = "$($Policy.Name)"
        enabled                      = $PolicyEnabled
        enableSpoofIntelligence      = [bool]$Policy.EnableSpoofIntelligence
        enableFirstContactSafetyTips = [bool]$Policy.EnableFirstContactSafetyTips
        enableUnauthenticatedSender  = [bool]$Policy.EnableUnauthenticatedSender
        enableViaTag                 = [bool]$Policy.EnableViaTag
        authenticationFailAction     = "$($Policy.AuthenticationFailAction)"
        spoofQuarantineTag           = "$($Policy.SpoofQuarantineTag)"
    }

    $ListParams = @{}
    if ($MDOLicensed) {
        $MdoExpected = [ordered]@{
            phishThresholdLevel                 = "$($V.PhishThresholdLevel)"
            enableMailboxIntelligence           = $true
            enableMailboxIntelligenceProtection = $true
            enableSimilarUsersSafetyTips        = [bool]($V.EnableSimilarUsersSafetyTips -eq $true)
            enableSimilarDomainsSafetyTips      = [bool]($V.EnableSimilarDomainsSafetyTips -eq $true)
            enableUnusualCharactersSafetyTips   = [bool]($V.EnableUnusualCharactersSafetyTips -eq $true)
            mailboxIntelligenceProtectionAction = "$($V.MailboxIntelligenceProtectionAction)"
            mailboxIntelligenceQuarantineTag    = "$($V.MailboxIntelligenceQuarantineTag)"
            targetedUserProtectionAction        = "$($V.TargetedUserProtectionAction)"
            targetedUserQuarantineTag           = "$($V.TargetedUserQuarantineTag)"
            targetedDomainProtectionAction      = "$($V.TargetedDomainProtectionAction)"
            targetedDomainQuarantineTag         = "$($V.TargetedDomainQuarantineTag)"
            enableTargetedDomainsProtection     = $true
            enableTargetedUserProtection        = $true
            enableOrganizationDomainsProtection = $true
        }
        $MdoCurrent = [ordered]@{
            phishThresholdLevel                 = "$($Policy.PhishThresholdLevel)"
            enableMailboxIntelligence           = [bool]$Policy.EnableMailboxIntelligence
            enableMailboxIntelligenceProtection = [bool]$Policy.EnableMailboxIntelligenceProtection
            enableSimilarUsersSafetyTips        = [bool]$Policy.EnableSimilarUsersSafetyTips
            enableSimilarDomainsSafetyTips      = [bool]$Policy.EnableSimilarDomainsSafetyTips
            enableUnusualCharactersSafetyTips   = [bool]$Policy.EnableUnusualCharactersSafetyTips
            mailboxIntelligenceProtectionAction = "$($Policy.MailboxIntelligenceProtectionAction)"
            mailboxIntelligenceQuarantineTag    = "$($Policy.MailboxIntelligenceQuarantineTag)"
            targetedUserProtectionAction        = "$($Policy.TargetedUserProtectionAction)"
            targetedUserQuarantineTag           = "$($Policy.TargetedUserQuarantineTag)"
            targetedDomainProtectionAction      = "$($Policy.TargetedDomainProtectionAction)"
            targetedDomainQuarantineTag         = "$($Policy.TargetedDomainQuarantineTag)"
            enableTargetedDomainsProtection     = [bool]$Policy.EnableTargetedDomainsProtection
            enableTargetedUserProtection        = [bool]$Policy.EnableTargetedUserProtection
            enableOrganizationDomainsProtection = [bool]$Policy.EnableOrganizationDomainsProtection
        }
        foreach ($Key in $MdoExpected.Keys) { $Expected.PSObject.Properties.Remove($Key); $Expected.PSObject.Properties.Add([psnoteproperty]::new($Key, $MdoExpected[$Key])) }
        foreach ($Key in $MdoCurrent.Keys) { $Current.PSObject.Properties.Remove($Key); $Current.PSObject.Properties.Add([psnoteproperty]::new($Key, $MdoCurrent[$Key])) }
        foreach ($List in $ProtectedLists) {
            $List.Desired.Sort($List.Live.Comparer)
            $DesiredSet = [System.Collections.Generic.HashSet[string]]::new($List.Desired, $List.Live.Comparer)
            $Missing = [System.Collections.Generic.List[string]]::new()
            foreach ($Entry in $List.Desired) { if (-not $List.Live.Contains($Entry)) { $Missing.Add($Entry) } }
            $Extra = [System.Collections.Generic.List[string]]::new()
            foreach ($Entry in $List.Live) { if (-not $DesiredSet.Contains($Entry)) { $Extra.Add($Entry) } }
            $Extra.Sort($List.Live.Comparer)
            $Want = '{0} ({1})' -f $List.Label, $List.Desired.Count
            $Delta = [System.Collections.Generic.List[string]]::new()
            if ($Missing.Count -gt 0) { $Delta.Add(('missing {0}: {1}{2}' -f $Missing.Count, ($Missing.GetRange(0, [Math]::Min(5, $Missing.Count)) -join ', '), $(if ($Missing.Count -gt 5) { " and $($Missing.Count - 5) more" }))) }
            if ($Extra.Count -gt 0) { $Delta.Add(('extra {0}: {1}{2}' -f $Extra.Count, ($Extra.GetRange(0, [Math]::Min(5, $Extra.Count)) -join ', '), $(if ($Extra.Count -gt 5) { " and $($Extra.Count - 5) more" }))) }
            if ($Delta.Count -gt 0) {
                try {
                    foreach ($Type in $List.CacheCounts.Keys) {
                        $Meta = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type -CountsOnly -ErrorAction Stop
                        if ($null -eq $Meta.DataCount -or $Meta.DataCount -ne $List.CacheCounts[$Type]) {
                            throw "the $Type cache row count does not match the collection metadata"
                        }
                        if ($UserScope -eq 'AllLicensed' -and (-not $Meta.Timestamp -or [DateTimeOffset]$Meta.Timestamp -lt [DateTimeOffset]::UtcNow.AddHours(-48))) {
                            throw "the $Type cache timestamp is missing or more than 48 hours old"
                        }
                    }
                } catch {
                    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "AntiPhishPolicy: the protected user list was left as it is and not graded because $($_.Exception.Message)." -Sev 'Warning'
                    continue
                }
                if ($List.Delta) {
                    $Change = @{ '@odata.type' = '#Exchange.GenericHashTable' }
                    if ($Missing.Count -gt 0) { $Change['Add'] = $Missing.ToArray() }
                    $Remove = [System.Collections.Generic.List[string]]::new()
                    foreach ($Entry in $Extra) { if ($List.Internal.ContainsKey($Entry)) { $Remove.Add($List.Internal[$Entry]) } }
                    if ($Remove.Count -gt 0) { $Change['Remove'] = $Remove.ToArray() }
                    if ($Change.Count -gt 1) { $ListParams[$List.Param] = $Change }
                } else {
                    $ListParams[$List.Param] = $List.Desired.ToArray()
                }
            }
            $Expected.PSObject.Properties.Remove($List.Key); $Expected.PSObject.Properties.Add([psnoteproperty]::new($List.Key, $Want))
            $Current.PSObject.Properties.Remove($List.Key); $Current.PSObject.Properties.Add([psnoteproperty]::new($List.Key, $(if ($Delta.Count -eq 0) { $Want } else { $Delta -join '; ' })))
        }
    }

    $Expected.PSObject.Properties.Remove('rule'); $Expected.PSObject.Properties.Add([psnoteproperty]::new('rule', ([PSCustomObject]@{
            name = $RuleName; policy = $PolicyName; priority = 0; recipientDomainIs = @($AcceptedDomains)
        })))
    $Current.PSObject.Properties.Remove('rule'); $Current.PSObject.Properties.Add([psnoteproperty]::new('rule', ([PSCustomObject]@{
            name              = "$($Rule.Name)"
            policy            = "$($Rule.AntiPhishPolicy)"
            priority          = $(if ($null -eq $Rule.Priority) { -1 } else { [int]$Rule.Priority })
            recipientDomainIs = @(@($Rule.RecipientDomainIs) | Where-Object { $_ } | Sort-Object)
        })))

    $Current.PSObject.Properties.Remove('policyName'); $Current.PSObject.Properties.Add([psnoteproperty]::new('policyName', $PolicyName))
    $Current.PSObject.Properties.Remove('ruleName'); $Current.PSObject.Properties.Add([psnoteproperty]::new('ruleName', $RuleName))
    $Current.PSObject.Properties.Remove('policyExists'); $Current.PSObject.Properties.Add([psnoteproperty]::new('policyExists', ([bool]$Policy)))
    $Current.PSObject.Properties.Remove('ruleExists'); $Current.PSObject.Properties.Add([psnoteproperty]::new('ruleExists', ([bool]$Rule)))
    $Current.PSObject.Properties.Remove('ruleLinkedPolicy'); $Current.PSObject.Properties.Add([psnoteproperty]::new('ruleLinkedPolicy', "$($Rule.AntiPhishPolicy)"))
    $Current.PSObject.Properties.Remove('acceptedDomains'); $Current.PSObject.Properties.Add([psnoteproperty]::new('acceptedDomains', @($AcceptedDomains)))
    $Current.PSObject.Properties.Remove('mdoLicensed'); $Current.PSObject.Properties.Add([psnoteproperty]::new('mdoLicensed', $MDOLicensed))
    # DERIVED write params the static remediate spec cannot express. Same derivations as
    # the graded Expected above, so grade and write can never disagree - these fifteen
    # were graded but never written, drifting forever. Blank optional actions/tags are
    # omitted: sending an empty enum errors, and the operator has not expressed intent.
    # Exchange rejects these on a tenant without Defender for Office 365.
    $ExtraPolicyParams = [ordered]@{}
    if ($MDOLicensed) {
        $ExtraPolicyParams = [ordered]@{
            EnableMailboxIntelligence           = $true
            EnableMailboxIntelligenceProtection = $true
            EnableTargetedDomainsProtection     = $true
            EnableTargetedUserProtection        = $true
            EnableOrganizationDomainsProtection = $true
            EnableSimilarUsersSafetyTips        = [bool]($V.EnableSimilarUsersSafetyTips -eq $true)
            EnableSimilarDomainsSafetyTips      = [bool]($V.EnableSimilarDomainsSafetyTips -eq $true)
            EnableUnusualCharactersSafetyTips   = [bool]($V.EnableUnusualCharactersSafetyTips -eq $true)
        }
        if (-not [string]::IsNullOrWhiteSpace("$($V.PhishThresholdLevel)")) { $ExtraPolicyParams['PhishThresholdLevel'] = [int]"$($V.PhishThresholdLevel)" }
        foreach ($ActionParam in @('MailboxIntelligenceProtectionAction', 'MailboxIntelligenceQuarantineTag', 'TargetedUserProtectionAction', 'TargetedUserQuarantineTag', 'TargetedDomainProtectionAction', 'TargetedDomainQuarantineTag')) {
            if (-not [string]::IsNullOrWhiteSpace("$($V.$ActionParam)")) { $ExtraPolicyParams[$ActionParam] = "$($V.$ActionParam)" }
        }
        foreach ($Param in $ListParams.Keys) { $ExtraPolicyParams[$Param] = $ListParams[$Param] }
    }
    $Current.PSObject.Properties.Remove('extraPolicyParams'); $Current.PSObject.Properties.Add([psnoteproperty]::new('extraPolicyParams', ([PSCustomObject]$ExtraPolicyParams)))

    @{ Expected = $Expected; Current = $Current }
}

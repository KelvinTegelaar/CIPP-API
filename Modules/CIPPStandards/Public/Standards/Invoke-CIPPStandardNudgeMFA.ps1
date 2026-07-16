function Invoke-CIPPStandardNudgeMFA {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) NudgeMFA
    .SYNOPSIS
        (Label) Sets the state for the request to setup Authenticator
    .DESCRIPTION
        (Helptext) Sets the state of the registration campaign for the tenant, including the targeted authentication method, snooze settings and include/exclude groups. Leave include/exclude blank to keep the groups currently configured in the tenant, or use 'AllUsers' to target all users.
        (DocsDescription) Sets the state of the registration campaign for the tenant. If enabled nudges users to set up the targeted authentication method (Microsoft Authenticator or a Passkey) during sign-in. Supports limiting the number of snoozes, and including or excluding specific groups (by display name).
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "ZTNA21889"
        EXECUTIVETEXT
            Prompts employees to set up multi-factor authentication during login, gradually improving the organization's security posture by encouraging adoption of stronger authentication methods. This helps achieve better security compliance without forcing immediate mandatory changes.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Registration campaign state","name":"standards.NudgeMFA.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"autoComplete","multiple":false,"creatable":false,"required":false,"label":"Authentication method to nudge users to register (default is Microsoft Authenticator)","name":"standards.NudgeMFA.targetedAuthenticationMethod","options":[{"label":"Microsoft Authenticator","value":"microsoftAuthenticator"},{"label":"Passkey (FIDO2)","value":"fido2"}],"condition":{"field":"standards.NudgeMFA.state","compareType":"valueEq","compareValue":"enabled"}}
            {"type":"number","name":"standards.NudgeMFA.snoozeDurationInDays","label":"Number of days to allow users to skip registering Authenticator (0-14, default is 1)","defaultValue":1,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":14,"message":"Maximum value is 14"}}}
            {"type":"switch","name":"standards.NudgeMFA.enforceRegistrationAfterAllowedSnoozes","label":"Limited number of snoozes (require registration after 3 snoozes)","defaultValue":true,"condition":{"field":"standards.NudgeMFA.state","compareType":"valueEq","compareValue":"enabled"}}
            {"type":"textField","name":"standards.NudgeMFA.includeTargets","label":"Include groups (comma separated group names, 'AllUsers' for everyone, blank = keep current targets)","required":false,"condition":{"field":"standards.NudgeMFA.state","compareType":"valueEq","compareValue":"enabled"}}
            {"type":"textField","name":"standards.NudgeMFA.excludeTargets","label":"Exclude groups (comma separated group names, blank = keep current exclusions)","required":false,"condition":{"field":"standards.NudgeMFA.state","compareType":"valueEq","compareValue":"enabled"}}
        IMPACT
            Low Impact
        ADDEDDATE
            2022-12-08
        POWERSHELLEQUIVALENT
            Update-MgPolicyAuthenticationMethodPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    # NOTE: The ADDEDCOMPONENT conditions above use compareType 'valueEq' rather than the usual 'is'.
    # The state field is an autoComplete which stores a {label, value} object, so 'is' (deep equality
    # against the raw string) never matches; 'valueEq' compares against the object's .value property
    # and is supported by CippFormCondition. Changing state to a 'select' field would allow 'is', but
    # would break existing saved NudgeMFA templates that already store the object shape.

    # Resolves comma separated group name entries to registration campaign targets
    function Resolve-NudgeMFATarget {
        param($Entries, $TenantFilter)
        $Resolved = [System.Collections.Generic.List[hashtable]]::new()
        $Failed = $false
        foreach ($Entry in $Entries) {
            try {
                if ($Entry -match '^(all_users|allusers|all users)$') {
                    $Resolved.Add(@{ id = 'all_users'; targetType = 'group' })
                } else {
                    $EscapedName = $Entry -replace "'", "''"
                    $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName')")
                    $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $TenantFilter)
                    if ($MatchedGroups.Count -gt 0) {
                        foreach ($Group in $MatchedGroups) { $Resolved.Add(@{ id = $Group.id; targetType = 'group' }) }
                        if ($MatchedGroups.Count -gt 1) {
                            Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "NudgeMFA: Multiple groups matched '$Entry': $($MatchedGroups.displayName -join ', ')" -sev Info
                        }
                    } else {
                        Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "NudgeMFA: No group found matching '$Entry'" -sev Warning
                        $Failed = $true
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "NudgeMFA: Failed to resolve target '$Entry'. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $Failed = $true
            }
        }
        return [PSCustomObject]@{ Targets = $Resolved; Failed = $Failed }
    }

    # Get state value using null-coalescing operator
    $State = $Settings.state.value ?? $Settings.state

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
        $CurrentCampaign = $CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign
    } catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to get Authenticator App Nudge state, check your permissions and try again' -sev Error -LogData (Get-CippException -Exception $_)
        return
    }

    $SnoozeDuration = [int]($Settings.snoozeDurationInDays ?? 1)
    $EnforceAfterSnoozes = if ($null -eq $Settings.enforceRegistrationAfterAllowedSnoozes) { $true } else { [bool]$Settings.enforceRegistrationAfterAllowedSnoozes }
    # Fall back to the method already targeted in the tenant so existing templates keep their current campaign type
    $TargetedMethod = $Settings.targetedAuthenticationMethod.value ?? $Settings.targetedAuthenticationMethod ?? (@($CurrentCampaign.includeTargets).targetedAuthenticationMethod | Select-Object -First 1) ?? 'microsoftAuthenticator'

    # NOTE: Unlike the AuthenticationMethods standard (where a blank group field means "All Users"),
    # blank include/exclude here means "keep the targets currently configured in the tenant". This is
    # deliberate: NudgeMFA predates these fields and existing deployments would otherwise have their
    # portal-configured targeting overwritten to all_users on the next run. Use the literal 'AllUsers'
    # entry to target everyone explicitly.
    $IncludeEntries = @(([string]($Settings.includeTargets ?? '')) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $ExcludeEntries = @(([string]($Settings.excludeTargets ?? '')) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # $Remediation*Targets are passed to Set-CIPPRegistrationCampaign ($null = keep current targets);
    # $Desired*Targets are the fully resolved lists used for the compliance comparison below.
    if ($IncludeEntries.Count -gt 0) {
        $IncludeResolution = Resolve-NudgeMFATarget -Entries $IncludeEntries -TenantFilter $Tenant
        if ($IncludeResolution.Failed -or $IncludeResolution.Targets.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'NudgeMFA: Could not resolve all include groups, skipping to avoid removing intended targets.' -sev Error
            return
        }
        $RemediationIncludeTargets = @($IncludeResolution.Targets)
        $DesiredIncludeTargets = @($RemediationIncludeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType; targetedAuthenticationMethod = $TargetedMethod } })
    } else {
        $RemediationIncludeTargets = $null
        $DesiredIncludeTargets = @($CurrentCampaign.includeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType; targetedAuthenticationMethod = $TargetedMethod } })
        if ($DesiredIncludeTargets.Count -eq 0) {
            $DesiredIncludeTargets = @(@{ id = 'all_users'; targetType = 'group'; targetedAuthenticationMethod = $TargetedMethod })
        }
    }

    $ManageExcludeTargets = $ExcludeEntries.Count -gt 0
    if ($ManageExcludeTargets) {
        $ExcludeResolution = Resolve-NudgeMFATarget -Entries $ExcludeEntries -TenantFilter $Tenant
        if ($ExcludeResolution.Failed) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'NudgeMFA: Could not resolve all exclude groups, skipping to avoid excluding the wrong groups.' -sev Error
            return
        }
        $RemediationExcludeTargets = @($ExcludeResolution.Targets)
        $DesiredExcludeTargets = @($RemediationExcludeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType } })
    } else {
        $RemediationExcludeTargets = $null
        $DesiredExcludeTargets = @($CurrentCampaign.excludeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType } })
    }

    $CurrentIncludeIds = @($CurrentCampaign.includeTargets.id)
    $DesiredIncludeIds = @($DesiredIncludeTargets.id)
    $IncludeIsCorrect = ($CurrentIncludeIds.Count -eq $DesiredIncludeIds.Count) -and
    (-not (Compare-Object -ReferenceObject @($DesiredIncludeIds | Sort-Object) -DifferenceObject @($CurrentIncludeIds | Sort-Object) -ErrorAction SilentlyContinue))
    $MethodIsCorrect = @($CurrentCampaign.includeTargets | Where-Object { $_.targetedAuthenticationMethod -ne $TargetedMethod }).Count -eq 0

    if ($ManageExcludeTargets) {
        $CurrentExcludeIds = @($CurrentCampaign.excludeTargets.id)
        $DesiredExcludeIds = @($DesiredExcludeTargets.id)
        $ExcludeIsCorrect = ($CurrentExcludeIds.Count -eq $DesiredExcludeIds.Count) -and
        (-not (Compare-Object -ReferenceObject @($DesiredExcludeIds | Sort-Object) -DifferenceObject @($CurrentExcludeIds | Sort-Object) -ErrorAction SilentlyContinue))
    } else {
        $ExcludeIsCorrect = $true
    }

    $StateIsCorrect = ($CurrentCampaign.state -eq $State) -and
    ([int]$CurrentCampaign.snoozeDurationInDays -eq $SnoozeDuration) -and
    ([bool]$CurrentCampaign.enforceRegistrationAfterAllowedSnoozes -eq $EnforceAfterSnoozes) -and
    $IncludeIsCorrect -and $MethodIsCorrect -and $ExcludeIsCorrect

    if ($Settings.remediate -eq $true) {
        $StateName = $State.Substring(0, 1).ToUpper() + $State.Substring(1)
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is already set to $State targeting $TargetedMethod with a snooze duration of $SnoozeDuration." -sev Info
        } else {
            try {
                $CampaignParams = @{
                    Tenant                                 = $Tenant
                    State                                  = $State
                    TargetedAuthenticationMethod           = $TargetedMethod
                    SnoozeDurationInDays                   = $SnoozeDuration
                    EnforceRegistrationAfterAllowedSnoozes = $EnforceAfterSnoozes
                    IncludeTargets                         = $RemediationIncludeTargets
                    ExcludeTargets                         = $RemediationExcludeTargets
                    APIName                                = 'Standards'
                }
                $null = Set-CIPPRegistrationCampaign @CampaignParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "$StateName Authenticator App Nudge targeting $TargetedMethod with a snooze duration of $SnoozeDuration" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Authenticator App Nudge to $State. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is configured correctly: $($CurrentCampaign.state) targeting $TargetedMethod with a snooze duration of $($CurrentCampaign.snoozeDurationInDays)" -sev Info
        } else {
            Write-StandardsAlert -message "Authenticator App Nudge is not configured as expected: state $($CurrentCampaign.state), snooze duration $($CurrentCampaign.snoozeDurationInDays)" -object ($CurrentCampaign | Select-Object state, snoozeDurationInDays, enforceRegistrationAfterAllowedSnoozes, includeTargets, excludeTargets) -tenant $Tenant -standardName 'NudgeMFA' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is not configured as expected: state $($CurrentCampaign.state), snooze duration $($CurrentCampaign.snoozeDurationInDays)" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            state                                  = $CurrentCampaign.state
            snoozeDurationInDays                   = $CurrentCampaign.snoozeDurationInDays
            enforceRegistrationAfterAllowedSnoozes = [bool]$CurrentCampaign.enforceRegistrationAfterAllowedSnoozes
            targetedAuthenticationMethod           = (@($CurrentCampaign.includeTargets).targetedAuthenticationMethod | Select-Object -First 1)
            includeTargets                         = @($CurrentCampaign.includeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType } })
            excludeTargets                         = @($CurrentCampaign.excludeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType } })
        }
        $ExpectedValue = @{
            state                                  = $State
            snoozeDurationInDays                   = $SnoozeDuration
            enforceRegistrationAfterAllowedSnoozes = $EnforceAfterSnoozes
            targetedAuthenticationMethod           = $TargetedMethod
            includeTargets                         = @($DesiredIncludeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType } })
            excludeTargets                         = $DesiredExcludeTargets
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.NudgeMFA' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'NudgeMFA' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}

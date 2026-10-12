function Get-CIPPBaselineNudgeMFAState {
    <#
    .SYNOPSIS
        Prepare hook for NudgeMFA: the authenticator registration campaign.
    .DESCRIPTION
        Grades the campaign's state, snooze duration, post-snooze enforcement, targeted
        method, and the include/exclude target sets. The targeting semantics are the
        classic's and they are DELIBERATE: blank include/exclude fields mean 'keep the
        targets currently configured in the tenant' - NudgeMFA predates those fields and
        existing deployments would otherwise have portal-configured targeting overwritten
        to all_users. The literal 'AllUsers' entry targets everyone explicitly.

        Group entries resolve from the Groups cache with the classic's startsWith rule,
        keeping EVERY match. An entry that resolves to nothing reports No Data - grading
        against a half-resolved target list would drift forever.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'AuthenticationMethodsPolicy') | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }
    $Campaign = $Policy.registrationEnforcement.authenticationMethodsRegistrationCampaign

    $V = $Item.Variables
    $State = "$($V.state.value ?? $V.state)"
    if ($State -notin @('enabled', 'disabled', 'default')) { return @{ Current = $null } }
    $Snooze = [int]"$($V.snoozeDurationInDays ?? 1)"
    $EnforceAfter = if ($null -eq $V.enforceRegistrationAfterAllowedSnoozes) { $true } else { [bool]($V.enforceRegistrationAfterAllowedSnoozes -eq $true) }
    $Method = "$($V.targetedAuthenticationMethod.value ?? $V.targetedAuthenticationMethod)"
    if ([string]::IsNullOrWhiteSpace($Method)) {
        $Method = "$((@($Campaign.includeTargets).targetedAuthenticationMethod | Select-Object -First 1) ?? 'microsoftAuthenticator')"
    }

    $IncludeEntries = @(("$($V.includeTargets)") -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $ExcludeEntries = @(("$($V.excludeTargets)") -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $Groups = @()
    if ($IncludeEntries.Count -gt 0 -or $ExcludeEntries.Count -gt 0) {
        $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
    }
    $Resolve = {
        param($Entries)
        $Resolved = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($Entry in $Entries) {
            if ($Entry -match '^(all_users|allusers|all users)$') { $Resolved.Add(@{ id = 'all_users'; targetType = 'group' }); continue }
            $Matched = @($Groups | Where-Object { "$($_.displayName)".StartsWith($Entry) })
            if ($Matched.Count -eq 0) { return $null }
            foreach ($Group in $Matched) { $Resolved.Add(@{ id = "$($Group.id)"; targetType = 'group' }) }
        }
        , @($Resolved)
    }

    if ($IncludeEntries.Count -gt 0) {
        $RemediationInclude = & $Resolve $IncludeEntries
        if ($null -eq $RemediationInclude -or @($RemediationInclude).Count -eq 0) { return @{ Current = $null } }
        $DesiredIncludeIds = @($RemediationInclude | ForEach-Object { $_.id })
    } else {
        $RemediationInclude = $null
        $DesiredIncludeIds = @($Campaign.includeTargets.id)
        if ($DesiredIncludeIds.Count -eq 0) { $DesiredIncludeIds = @('all_users') }
    }
    if ($ExcludeEntries.Count -gt 0) {
        $RemediationExclude = & $Resolve $ExcludeEntries
        if ($null -eq $RemediationExclude) { return @{ Current = $null } }
        $DesiredExcludeIds = @($RemediationExclude | ForEach-Object { $_.id })
    } else {
        $RemediationExclude = $null
        $DesiredExcludeIds = @($Campaign.excludeTargets.id)
    }

    $Expected = [PSCustomObject]@{
        state                                  = $State
        snoozeDurationInDays                   = $Snooze
        enforceRegistrationAfterAllowedSnoozes = $EnforceAfter
        targetedMethodCorrect                  = $true
        includeTargetIds                       = @($DesiredIncludeIds | Sort-Object)
    }
    $Current = [PSCustomObject]@{
        state                                  = "$($Campaign.state)"
        snoozeDurationInDays                   = [int]"$($Campaign.snoozeDurationInDays)"
        enforceRegistrationAfterAllowedSnoozes = [bool]$Campaign.enforceRegistrationAfterAllowedSnoozes
        targetedMethodCorrect                  = (@($Campaign.includeTargets | Where-Object { "$($_.targetedAuthenticationMethod)" -ne $Method }).Count -eq 0)
        includeTargetIds                       = @($Campaign.includeTargets.id | Sort-Object)
    }
    if ($ExcludeEntries.Count -gt 0) {
        $Expected | Add-Member -NotePropertyName 'excludeTargetIds' -NotePropertyValue @($DesiredExcludeIds | Sort-Object)
        $Current | Add-Member -NotePropertyName 'excludeTargetIds' -NotePropertyValue @($Campaign.excludeTargets.id | Sort-Object)
    }
    # Carried for the executor: Set-CIPPRegistrationCampaign's inputs ($null = keep current).
    $Current | Add-Member -NotePropertyName 'campaignParams' -NotePropertyValue ([PSCustomObject]@{
            State = $State; TargetedAuthenticationMethod = $Method; SnoozeDurationInDays = $Snooze
            EnforceRegistrationAfterAllowedSnoozes = $EnforceAfter
            IncludeTargets = $RemediationInclude; ExcludeTargets = $RemediationExclude
        })

    @{ Expected = $Expected; Current = $Current }
}

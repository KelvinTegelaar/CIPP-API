function Test-CIPPOffboardingRequest {
    <#
    .SYNOPSIS
        Validates the shape of an ExecOffboardUser request body before a scheduled task is queued.
    .DESCRIPTION
        Invoke-ExecOffboardUser queues an asynchronous scheduled task and returns 200 the instant the
        task is created - it never waits for, or reports on, the actual offboarding result. That means a
        malformed payload silently "succeeds": it reports OK, queues nothing useful, runs no actions, and
        never appears in the Offboarding view.

        The common failure modes this catches:
          - 'user' sent as bare UPN strings instead of { value = '<upn>' } objects, so the backend's
            $Request.Body.user.value resolves to nothing and no task is created.
          - 'tenantFilter' missing or not resolvable to a domain.
          - 'Scheduled.enabled' true with a missing/invalid date.
          - No offboarding actions selected, which produces an empty batch that completes as a no-op.

        Returns a structured result. The endpoint rejects the request with a 400 when IsValid is false,
        and reuses the normalized TenantFilter/Users so the extraction logic matches what was validated.
    .PARAMETER Body
        The $Request.Body of the ExecOffboardUser call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Body
    )

    $Errors = [System.Collections.Generic.List[string]]::new()

    # tenantFilter: required, must resolve to a non-empty domain string (accepts a string or { value })
    $TenantFilter = $Body.tenantFilter.value ?? $Body.tenantFilter
    if ([string]::IsNullOrWhiteSpace([string]$TenantFilter)) {
        $Errors.Add("'tenantFilter' is required and must resolve to a tenant domain (a string, or an object with a non-empty 'value' property).")
    }

    # user: required, >= 1 entry, each resolving to a non-empty userPrincipalName.
    # Accepts the UI shape ([{ value = '<upn>' }]) and bare UPN strings (['<upn>']).
    # Only string values are accepted - an object without a 'value' must NOT fall back to the object
    # itself (its string form is "@{...}", which would otherwise sneak past the UPN '@' check).
    $Users = @(
        $Body.user | ForEach-Object {
            $UserValue = $_.value ?? $_
            if ($UserValue -is [string]) { $UserValue }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if (-not $Body.user -or @($Body.user).Count -eq 0) {
        $Errors.Add("'user' is required and must be a non-empty array of users (objects with a 'value' property, or userPrincipalName strings).")
    } elseif ($Users.Count -eq 0) {
        $Errors.Add("'user' did not resolve to any usable userPrincipalName. Each entry must be a UPN string or an object with a non-empty 'value' property.")
    } else {
        $InvalidUsers = @($Users | Where-Object { [string]$_ -notmatch '@' })
        if ($InvalidUsers.Count -gt 0) {
            $Errors.Add("These user values do not look like userPrincipalNames (missing '@'): $($InvalidUsers -join ', ').")
        }
    }

    # Scheduled: when enabled, date must be a valid Unix timestamp
    if ($Body.Scheduled.enabled) {
        $Epoch = [int64]0
        if ($null -eq $Body.Scheduled.date -or -not [int64]::TryParse([string]$Body.Scheduled.date, [ref]$Epoch) -or $Epoch -le 0) {
            $Errors.Add("'Scheduled.enabled' is true but 'Scheduled.date' is not a valid Unix timestamp.")
        }
    }

    # At least one offboarding action must be selected, otherwise the job builds an empty batch and no-ops.
    # Keep this list in sync with the conditions in Invoke-CIPPOffboardingJob.
    $BooleanActions = @(
        'ConvertToShared', 'HideFromGAL', 'removeCalendarInvites', 'removePermissions', 'removeCalendarPermissions',
        'RemoveRules', 'RemoveMobile', 'RemoveGroups', 'RemoveLicenses', 'RevokeSessions', 'DisableSignIn',
        'ClearImmutableId', 'ResetPass', 'RemoveMFADevices', 'RemoveTeamsPhoneDID', 'DeleteUser',
        'DisableOneDriveSharing', 'disableForwarding'
    )
    $CollectionActions = @('AccessNoAutomap', 'AccessAutomap', 'OnedriveAccess')

    $HasAction = $false
    foreach ($Key in $BooleanActions) {
        if ($Body.$Key -eq $true) { $HasAction = $true; break }
    }
    if (-not $HasAction) {
        foreach ($Key in $CollectionActions) {
            if (@($Body.$Key | Where-Object { $null -ne $_ }).Count -gt 0) { $HasAction = $true; break }
        }
    }
    if (-not $HasAction -and -not [string]::IsNullOrWhiteSpace([string]($Body.forward.value ?? $Body.forward))) {
        $HasAction = $true
    }
    if (-not $HasAction -and -not [string]::IsNullOrWhiteSpace([string]$Body.OOO)) {
        $HasAction = $true
    }
    if (-not $HasAction) {
        $Errors.Add('No offboarding actions were selected. Enable at least one action (e.g. RemoveLicenses, DisableSignIn, RevokeSessions) before submitting.')
    }

    return [PSCustomObject]@{
        IsValid      = ($Errors.Count -eq 0)
        Errors       = @($Errors)
        TenantFilter = $TenantFilter
        Users        = $Users
    }
}

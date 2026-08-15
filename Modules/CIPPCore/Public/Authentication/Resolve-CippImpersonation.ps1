function Resolve-CippImpersonation {
    <#
    .SYNOPSIS
        Superadmin-only role impersonation for interactive requests.
    .DESCRIPTION
        When a real superadmin sends x-cipp-impersonate-role, returns a replacement user
        object holding only that role, so every downstream check (IP ranges, /me, base and
        custom role evaluation, tenant scoping) sees the impersonated role. Anyone else's
        header is ignored, so the swap can only ever narrow privileges. Cheap and
        deterministic on purpose: it runs up to three times per request.
    .PARAMETER User
        The decoded x-ms-client-principal user object.
    .PARAMETER Request
        The HTTP request (headers are read for the impersonation target and audit logging).
    #>
    [CmdletBinding()]
    param($User, $Request)

    $Result = [pscustomobject]@{
        User          = $User
        Impersonating = $null
        RealRoles     = @($User.userRoles | Where-Object { $_ -notin @('anonymous', 'authenticated') })
    }
    $Target = $Request.Headers.'x-cipp-impersonate-role'
    if ([string]::IsNullOrWhiteSpace($Target)) { return $Result }

    # Only a real superadmin may impersonate; everyone else is a silent no-op.
    if (@($User.userRoles) -notcontains 'superadmin') {
        Write-Warning "Ignoring impersonation header from non-superadmin principal '$($User.userDetails)'"
        return $Result
    }

    # Role RowKeys are stored lowercased (Invoke-ExecCustomRole).
    $Target = $Target.Trim().ToLower()
    if ($Target -eq 'superadmin') {
        throw 'Impersonating the superadmin role is not allowed'
    }

    # Base roles skip the table read; custom roles must exist. Fail closed: a deleted role
    # must not silently restore superadmin while the UI banner still claims impersonation.
    if ($Target -notin @('readonly', 'editor', 'admin')) {
        try {
            $null = Get-CIPPRolePermissions -RoleName $Target
        } catch {
            throw "Impersonation target role '$Target' does not exist"
        }
    }

    # Build a FRESH object: Test-CIPPAccessUserRole caches the roles array per worker by
    # reference, so mutating $User.userRoles would poison the real user's cached roles.
    # authenticated/anonymous stay because downstream default-role filtering expects them.
    $Result.User = [pscustomobject]@{
        identityProvider = $User.identityProvider
        userId           = $User.userId
        userDetails      = $User.userDetails
        userRoles        = @('authenticated', 'anonymous', $Target)
    }
    $Result.Impersonating = $Target

    # Audit once per worker per (user, role); per-request would flood CippLogs. Deliberately
    # per-worker state - do not reset per request. Write-LogMessage resolves the REAL
    # username from the principal headers regardless of the swap.
    if (-not $script:CippImpersonationLogged) { $script:CippImpersonationLogged = @{} }
    $AuditKey = '{0}|{1}' -f $User.userDetails, $Target
    if (-not $script:CippImpersonationLogged.ContainsKey($AuditKey)) {
        $script:CippImpersonationLogged[$AuditKey] = $true
        Write-LogMessage -headers $Request.Headers -API 'Impersonation' -Sev 'Info' `
            -message "Superadmin '$($User.userDetails)' is impersonating role '$Target'" `
            -LogData @{ ImpersonatedRole = $Target; RealRoles = $Result.RealRoles }
    }
    return $Result
}

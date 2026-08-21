function Invoke-CIPPBaselineDisableBasicAuthSMTP {
    <#
    .SYNOPSIS
        DisableBasicAuthSMTP executor: sets the tenant transport flag and clears per-user
        SMTP AUTH overrides.
    .DESCRIPTION
        Needs its own executor because the second half of the write is a SWEEP: one
        Set-CASMailbox per user who has SMTP AUTH explicitly enabled. The offender list is
        not a constant - it comes from -Current, the object the prepare hook already
        computed, so the write targets exactly what the compare graded.

        Overrides are cleared back to inherit ($null), never $true, so a later tenant-level
        policy change applies to those users again. Only relevant when disabling: an
        operator who set the flag to enabled has not asked for enablements to be stripped,
        and the prepare hook does not grade them either.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Disabled = [bool]($Remediate.disabled -eq $true)
    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-TransportConfig' -cmdParams @{ SmtpClientAuthenticationDisabled = $Disabled }
    if (-not $Disabled) { return }

    $EnabledUsers = @($Current.UsersWithSmtpAuthEnabled | Where-Object { $_ })
    foreach ($User in $EnabledUsers) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams @{ Identity = $User; SmtpClientAuthenticationDisabled = $null }
    }

    if ($EnabledUsers.Count -gt 0) {
        # Refresh the override cache now: the cleared users must not read back as drift on
        # the next run (ClearOnEmpty makes the emptied state stick).
        $Collector = Get-Command -Name 'Set-CIPPDBCacheExoCASMailboxSmtpAuth' -ErrorAction SilentlyContinue
        if ($Collector) {
            try { $null = & $Collector -TenantFilter $TenantFilter } catch {
                Write-Information "Baselines: SMTP AUTH override cache refresh on $TenantFilter failed: $($_.Exception.Message)"
            }
        }
    }
}

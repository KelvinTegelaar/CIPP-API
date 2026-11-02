function Get-CIPPBaselineDisableBasicAuthSMTPState {
    <#
    .SYNOPSIS
        Prepare hook for DisableBasicAuthSMTP: joins the tenant-wide transport flag with
        the per-user CAS mailbox overrides into one comparable object.
    .DESCRIPTION
        Two dimensions, which is why this standard needs a hook: the TransportConfig
        SmtpClientAuthenticationDisabled flag AND the per-user overrides
        (SmtpClientAuthenticationDisabled -eq $false = SMTP AUTH explicitly enabled for
        that user, alive regardless of the tenant switch). They live in two cache types,
        and a declarative read selects from one.

        Expected IS returned, because its SHAPE is conditional: the override list is only
        graded when the point is disabling SMTP AUTH. An operator who deliberately sets
        the flag to enabled has not asked for per-user enablements to be stripped, so that
        key is dropped from both sides rather than compared against an empty list.

        A null Current is the honest 'not collected' signal for the transport config - the
        engine triggers the collector, retries once, then parks at No Data. The override
        cache is this hook's own business: an empty read there is ambiguous (never
        collected vs genuinely none), so it always re-collects once - the collector's
        ClearOnEmpty makes the collected-empty state authoritative and the recollect cheap.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $TransportConfig = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ExoTransportConfig' | Where-Object { $_ }) | Select-Object -First 1
    if ($null -eq $TransportConfig) { return @{ Current = $null } }

    $ExpectedDisabled = "$($Item.Variables.disabled)" -in @('True', 'true', '1')

    $Overrides = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoCASMailboxSmtpAuth')
    $EnabledUsers = @($Overrides | ForEach-Object { "$($_.PrimarySmtpAddress ?? $_.Identity)" } | Where-Object { $_ } | Sort-Object)

    $Expected = [PSCustomObject]@{ SmtpClientAuthenticationDisabled = $ExpectedDisabled }
    $Current = [PSCustomObject]@{ SmtpClientAuthenticationDisabled = [bool]$TransportConfig.SmtpClientAuthenticationDisabled }
    if ($ExpectedDisabled) {
        $Expected | Add-Member -NotePropertyName 'UsersWithSmtpAuthEnabled' -NotePropertyValue @()
        $Current | Add-Member -NotePropertyName 'UsersWithSmtpAuthEnabled' -NotePropertyValue $EnabledUsers
    }

    @{ Expected = $Expected; Current = $Current }
}

function Invoke-CIPPBaselineRotateDKIM {
    <#
    .SYNOPSIS
        RotateDKIM executor: rotates weak DKIM keys to 2048-bit.
    .DESCRIPTION
        One Rotate-DkimSigningConfig per domain the hook found on a 1024-bit selector.
        Rotation is asynchronous in Exchange - the new key publishes on the next selector
        flip - so the row stays at drift until Exchange reports the new key size, which is
        the honest state.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Domains = @($Current.domainsWith1024BitDkim | Where-Object { $_ })
    if ($Domains.Count -eq 0) { return }

    foreach ($Domain in $Domains) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Rotate-DkimSigningConfig' -cmdParams @{ KeySize = 2048; Identity = "$Domain" } -useSystemMailbox $true
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Rotated DKIM to 2048-bit for: $($Domains -join ', ')." -Sev 'Info'
}

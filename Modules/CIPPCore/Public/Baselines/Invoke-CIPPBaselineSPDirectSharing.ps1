function Invoke-CIPPBaselineSPDirectSharing {
    <#
    .SYNOPSIS
        SPDirectSharing executor: sets the default sharing link type to Direct.
    .DESCRIPTION
        Reads the SPO tenant LIVE for a fresh CSOM object identity - the cached one goes
        stale and the SPO SOAP endpoint rejects stale identities - then writes
        DefaultSharingLinkType 1 through the shared SPO helper, the classic's write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $State = Get-CIPPSPOTenant -TenantFilter $TenantFilter | Select-Object -Property _ObjectIdentity_, TenantFilter, DefaultSharingLinkType
    if (-not $State) { throw 'Could not read the SPO tenant configuration - refusing a blind write.' }
    $State | Set-CIPPSPOTenant -Properties @{ DefaultSharingLinkType = 1 }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Set the default sharing link type to Direct.' -Sev 'Info'
}

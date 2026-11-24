function Invoke-CIPPBaselineCrossTenantPartner {
    <#
    .SYNOPSIS
        CrossTenantPartner executor: adds or updates one partner organisation.
    .DESCRIPTION
        Passes the configured settings to Set-CIPPCrossTenantAccess, which reads the partner
        live, creates it when missing and merges trust flags it was not given.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Settings = @{}
    foreach ($Key in 'b2bCollaborationInbound', 'b2bCollaborationOutbound', 'b2bDirectConnectInbound', 'b2bDirectConnectOutbound',
        'isMfaAccepted', 'isCompliantDeviceAccepted', 'isHybridAzureADJoinedDeviceAccepted', 'inboundAllowed', 'outboundAllowed') {
        $Value = "$($Remediate.$Key.value ?? $Remediate.$Key)"
        if ($Value) { $Settings[$Key] = $Value }
    }
    $PartnerTenantId = "$($Remediate.partnerTenantId.value ?? $Remediate.partnerTenantId)".Trim()
    # An instance with only the partner configured still has to create it.
    if ($Settings.Count -eq 0 -and $Current.exists -ne $true) { $Settings['b2bCollaborationInbound'] = 'inherit' }

    $Result = Set-CIPPCrossTenantAccess -TenantFilter $TenantFilter -PartnerTenantId $PartnerTenantId -Settings $Settings
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message $Result -Sev 'Info'
}

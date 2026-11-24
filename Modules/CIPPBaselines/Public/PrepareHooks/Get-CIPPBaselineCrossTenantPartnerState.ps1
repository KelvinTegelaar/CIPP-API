function Get-CIPPBaselineCrossTenantPartnerState {
    <#
    .SYNOPSIS
        Prepare hook for CrossTenantPartner: does the partner exist, with the configured settings.
    .DESCRIPTION
        One instance grades ONE partner organisation from the CrossTenantPartners cache. A tenant
        with no partners is a real answer (the type was collected and is empty), so it grades as
        drift rather than No Data. Access directions read as allowed / blocked only when they
        cover all users and all applications, inherit when the partner has no override, and
        custom otherwise. Trust grades the partner's own inboundTrust, so an inherited trust
        reads as inherit and drifts against an explicit Trust / Don't trust.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $V = $Item.Variables
    $PartnerTenantId = "$($V.partnerTenantId.value ?? $V.partnerTenantId)".Trim()
    $ParsedId = [guid]::Empty
    if (-not [guid]::TryParse($PartnerTenantId, [ref]$ParsedId)) {
        return @{ Current = $null; NoDataReason = "the configured partner '$PartnerTenantId' is not a tenant ID"; ConfigError = $true }
    }

    $Partners = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'CrossTenantPartners')
    if ($Partners.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'CrossTenantPartners')) {
        return @{ Current = $null }
    }
    $Partner = $null
    foreach ($Row in $Partners) {
        if ("$($Row.tenantId)" -eq $PartnerTenantId) { $Partner = $Row; break }
    }

    $Expected = [ordered]@{ exists = $true }
    $Current = [ordered]@{ exists = $null -ne $Partner }
    foreach ($Direction in 'b2bCollaborationInbound', 'b2bCollaborationOutbound', 'b2bDirectConnectInbound', 'b2bDirectConnectOutbound') {
        $Want = "$($V.$Direction.value ?? $V.$Direction)"
        if (-not $Want) { continue }
        $Expected[$Direction] = $Want
        $Setting = $Partner.$Direction
        $Current[$Direction] = if (-not $Partner) { $null } elseif (-not $Setting) { 'inherit' } else {
            $Users = $Setting.usersAndGroups
            $Apps = $Setting.applications
            if ($Users.accessType -eq $Apps.accessType -and
                @($Users.targets).Count -eq 1 -and "$(@($Users.targets)[0].target)" -eq 'AllUsers' -and
                @($Apps.targets).Count -eq 1 -and "$(@($Apps.targets)[0].target)" -eq 'AllApplications') {
                "$($Users.accessType)"
            } else { 'custom' }
        }
    }
    foreach ($Flag in 'isMfaAccepted', 'isCompliantDeviceAccepted', 'isHybridAzureADJoinedDeviceAccepted') {
        $Want = "$($V.$Flag.value ?? $V.$Flag)"
        if (-not $Want) { continue }
        $Expected[$Flag] = $Want -eq 'true'
        $Current[$Flag] = if (-not $Partner) { $null } elseif (-not $Partner.inboundTrust) { 'inherit' } else { $Partner.inboundTrust.$Flag -eq $true }
    }
    foreach ($Flag in 'inboundAllowed', 'outboundAllowed') {
        $Want = "$($V.$Flag.value ?? $V.$Flag)"
        if (-not $Want) { continue }
        $Expected[$Flag] = $Want -eq 'true'
        $Current[$Flag] = if ($Partner) { $Partner.automaticUserConsentSettings.$Flag -eq $true } else { $null }
    }

    @{
        Expected = [PSCustomObject]$Expected
        Current  = [PSCustomObject]$Current
    }
}

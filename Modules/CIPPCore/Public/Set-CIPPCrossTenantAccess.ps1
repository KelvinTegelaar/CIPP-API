function Set-CIPPCrossTenantAccess {
    <#
    .SYNOPSIS
        Updates the default cross-tenant access policy, or creates or updates a partner organisation
    .DESCRIPTION
        Settings holds only what changes:
        - b2bCollaborationInbound/Outbound, b2bDirectConnectInbound/Outbound: allowed or blocked (all
          users and all applications), or inherit (partners only) to fall back to the default policy.
        - isMfaAccepted, isCompliantDeviceAccepted, isHybridAzureADJoinedDeviceAccepted: inbound trust.
          Graph replaces the whole inboundTrust object, so unset flags keep their current value; a
          partner without its own trust starts from the default policy's. inboundTrust = inherit
          (partners only) clears the partner's trust instead.
        - inboundAllowed, outboundAllowed: automatic invitation redemption (partners only).
        A partner that does not exist yet is created. Returns a result message.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        # Empty for the default policy
        [string]$PartnerTenantId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    $IsDefault = [string]::IsNullOrWhiteSpace($PartnerTenantId)
    $ParsedId = [guid]::Empty
    if (-not $IsDefault -and -not [guid]::TryParse($PartnerTenantId, [ref]$ParsedId)) {
        throw [System.ArgumentException]::new("'$PartnerTenantId' is not a tenant ID.")
    }
    $BaseUri = 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy'
    $TrustFlags = @('isMfaAccepted', 'isCompliantDeviceAccepted', 'isHybridAzureADJoinedDeviceAccepted')
    $InheritTrust = "$($Settings['inboundTrust'])" -eq 'inherit'
    $SetsTrust = -not $InheritTrust -and $TrustFlags.Where({ $Settings.ContainsKey($_) }).Count -gt 0
    $SetsRedemption = $Settings.ContainsKey('inboundAllowed') -or $Settings.ContainsKey('outboundAllowed')
    if ($IsDefault -and ($InheritTrust -or $SetsRedemption)) {
        throw [System.ArgumentException]::new('Trust inheritance and automatic redemption can only be set on a partner organisation.')
    }

    $Body = @{}
    foreach ($Direction in 'b2bCollaborationInbound', 'b2bCollaborationOutbound', 'b2bDirectConnectInbound', 'b2bDirectConnectOutbound') {
        if (-not $Settings.ContainsKey($Direction)) { continue }
        $Access = "$($Settings[$Direction])"
        if ($Access -eq 'inherit' -and -not $IsDefault) {
            $Body[$Direction] = $null
            continue
        }
        if ($Access -notin 'allowed', 'blocked') {
            throw [System.ArgumentException]::new("$Direction must be allowed or blocked$(if (-not $IsDefault) { ', or inherit' }), not '$Access'.")
        }
        $Body[$Direction] = @{
            usersAndGroups = @{ accessType = $Access; targets = @(@{ target = 'AllUsers'; targetType = 'user' }) }
            applications   = @{ accessType = $Access; targets = @(@{ target = 'AllApplications'; targetType = 'application' }) }
        }
    }

    $Existing = $null
    if (-not $IsDefault) {
        $Existing = @(New-GraphGetRequest -uri "$BaseUri/partners" -tenantid $TenantFilter -AsApp $true).Where({ $_.tenantId -eq $PartnerTenantId }, 'First')[0]
    }

    if ($InheritTrust) {
        $Body['inboundTrust'] = $null
    } elseif ($SetsTrust) {
        $CurrentTrust = $Existing.inboundTrust
        if (-not $CurrentTrust) {
            $CurrentTrust = (New-GraphGetRequest -uri "$BaseUri/default?`$select=inboundTrust" -tenantid $TenantFilter -AsApp $true).inboundTrust
            if (-not $CurrentTrust) { throw 'Could not read the current inbound trust settings - refusing a blind write.' }
        }
        $Trust = @{}
        foreach ($Flag in $TrustFlags) {
            $Trust[$Flag] = if ($Settings.ContainsKey($Flag)) { "$($Settings[$Flag])" -eq 'true' } else { $CurrentTrust.$Flag -eq $true }
        }
        $Body['inboundTrust'] = $Trust
    }

    if ($SetsRedemption) {
        $Consent = @{}
        foreach ($Flag in 'inboundAllowed', 'outboundAllowed') {
            $Consent[$Flag] = if ($Settings.ContainsKey($Flag)) { "$($Settings[$Flag])" -eq 'true' } else { $Existing.automaticUserConsentSettings.$Flag -eq $true }
        }
        $Body['automaticUserConsentSettings'] = $Consent
    }

    if ($Body.Count -eq 0) { throw [System.ArgumentException]::new('No settings to change.') }

    if ($IsDefault) {
        $null = New-GraphPostRequest -uri "$BaseUri/default" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -Depth 10 -Compress -InputObject $Body) -AsApp $true
        return 'Updated the default cross-tenant access settings. Changes can take a minute to show.'
    }
    if ($Existing) {
        $null = New-GraphPostRequest -uri "$BaseUri/partners/$PartnerTenantId" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -Depth 10 -Compress -InputObject $Body) -AsApp $true
        return "Updated partner organisation $PartnerTenantId. Changes can take a minute to show."
    }
    $Body['tenantId'] = $PartnerTenantId
    $null = New-GraphPostRequest -uri "$BaseUri/partners" -tenantid $TenantFilter -type POST -body (ConvertTo-Json -Depth 10 -Compress -InputObject $Body) -AsApp $true
    return "Added partner organisation $PartnerTenantId. It can take a minute to show in the list."
}

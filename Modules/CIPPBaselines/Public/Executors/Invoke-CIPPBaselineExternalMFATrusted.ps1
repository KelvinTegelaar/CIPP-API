function Invoke-CIPPBaselineExternalMFATrusted {
    <#
    .SYNOPSIS
        ExternalMFATrusted executor: sets inbound MFA trust on the default cross-tenant
        access policy.
    .DESCRIPTION
        Reads the policy LIVE and patches the merged inboundTrust object, never the single
        flag: Graph replaces the whole complex value on PATCH, so a bare isMfaAccepted body
        would silently reset the compliant-device and hybrid-join trust flags alongside it.
        The classic did the same read-merge-write for the same reason.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Policy = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default?$select=inboundTrust' -tenantid $TenantFilter
    if (-not $Policy.inboundTrust) { throw 'Could not read the default cross-tenant access policy - refusing a blind write.' }

    $Policy.inboundTrust.isMfaAccepted = [bool]($Remediate.trusted -eq $true -or "$($Remediate.trusted)" -eq 'True')
    $Body = ConvertTo-Json -Compress -Depth 10 -InputObject ([PSCustomObject]@{ inboundTrust = $Policy.inboundTrust })
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default' -type PATCH -body $Body
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set external MFA trust to $($Policy.inboundTrust.isMfaAccepted)." -Sev 'Info'
}

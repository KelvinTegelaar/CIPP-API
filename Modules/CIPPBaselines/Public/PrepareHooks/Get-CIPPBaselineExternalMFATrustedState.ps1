function Get-CIPPBaselineExternalMFATrustedState {
    <#
    .SYNOPSIS
        Prepare hook for ExternalMFATrusted: does the tenant trust MFA from external tenants.
    .DESCRIPTION
        One graded boolean, read from the default cross-tenant access policy's inboundTrust.
        A hook rather than a declarative expected because the operator's switch has to grade
        in BOTH directions - trusting external MFA and deliberately not trusting it are both
        valid postures, and the classic offered exactly that choice.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'CrossTenantAccessPolicy') | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }

    @{
        Expected = [PSCustomObject]@{ isMfaAccepted = [bool]($Item.Variables.state -eq $true) }
        Current  = [PSCustomObject]@{ isMfaAccepted = [bool]$Policy.inboundTrust.isMfaAccepted }
    }
}

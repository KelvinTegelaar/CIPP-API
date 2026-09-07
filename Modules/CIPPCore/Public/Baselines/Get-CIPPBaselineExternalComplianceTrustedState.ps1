function Get-CIPPBaselineExternalComplianceTrustedState {
    <#
    .SYNOPSIS
        Prepare hook for ExternalComplianceTrusted: does the tenant trust device compliance from external tenants.
    .DESCRIPTION
        One graded boolean, read from the default cross-tenant access policy's inboundTrust.
        A hook rather than a declarative expected because the operator's switch has to grade
        in BOTH directions - trusting external device compliance and deliberately not trusting it
        are both valid postures.
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
        Expected = [PSCustomObject]@{ isCompliantDeviceAccepted = [bool]($Item.Variables.state -eq $true) }
        Current  = [PSCustomObject]@{ isCompliantDeviceAccepted = [bool]$Policy.inboundTrust.isCompliantDeviceAccepted }
    }
}

function Get-CIPPBaselineDeviceRegistrationPolicyState {
    <#
    .SYNOPSIS
        Shared prepare hook for the six standards that govern policies/deviceRegistrationPolicy.
    .DESCRIPTION
        Flattens the cached policy into one scalar per governed setting. Two reasons it
        cannot be read declaratively:

        1. Three of the settings ARE an '@odata.type' value (allowedToJoin,
           allowedToRegister, localAdmins.registeringUsers). Compare-CIPPIntuneObject skips
           every property matching '*@OData*' - correctly, because everywhere else that key
           is Graph metadata rather than a value. Compared in place they would be silently
           ignored, scoring Compliant forever and never remediating. Lifting them to plain
           properties is what makes them gradeable.
        2. The projection hands a prepared sub-object to the compare WHOLE, and the compare
           reports properties present only on the current side as drift. A nested shape
           would therefore flag siblings like isAdminConfigurable. Flat scalars have no
           siblings, so each definition grades exactly the keys it declares.

        The write is the raw Graph shape and lives in the executor - the two are deliberately
        different vocabularies: this one is for grading, that one is for merging.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'DeviceRegistrationPolicy' | Where-Object { $_ }) | Select-Object -First 1
    if ($null -eq $Policy) { return @{ Current = $null } }

    @{
        Current = [PSCustomObject]@{
            userDeviceQuota               = $Policy.userDeviceQuota
            multiFactorAuthConfiguration  = $Policy.multiFactorAuthConfiguration
            localAdminPasswordEnabled     = [bool]$Policy.localAdminPassword.isEnabled
            allowedToJoin                 = "$($Policy.azureADJoin.allowedToJoin.'@odata.type')"
            allowedToRegister             = "$($Policy.azureADRegistration.allowedToRegister.'@odata.type')"
            localAdminsRegisteringUsers   = "$($Policy.azureADJoin.localAdmins.registeringUsers.'@odata.type')"
            localAdminsEnableGlobalAdmins = [bool]$Policy.azureADJoin.localAdmins.enableGlobalAdmins
        }
    }
}

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

    $Current = [PSCustomObject]@{
        userDeviceQuota               = $Policy.userDeviceQuota
        multiFactorAuthConfiguration  = $Policy.multiFactorAuthConfiguration
        localAdminPasswordEnabled     = [bool]$Policy.localAdminPassword.isEnabled
        allowedToJoin                 = "$($Policy.azureADJoin.allowedToJoin.'@odata.type')"
        allowedToRegister             = "$($Policy.azureADRegistration.allowedToRegister.'@odata.type')"
        localAdminsRegisteringUsers   = "$($Policy.azureADJoin.localAdmins.registeringUsers.'@odata.type')"
        localAdminsEnableGlobalAdmins = [bool]$Policy.azureADJoin.localAdmins.enableGlobalAdmins
    }

    $JoinType = "$($Item.Variables.allowedToJoin.value ?? $Item.Variables.allowedToJoin)"
    if ($JoinType -ne '#microsoft.graph.enumeratedDeviceRegistrationMembership') { return @{ Current = $Current } }

    # Selected groups: comma separated names or ids; a list variable arrives here already joined with commas
    $Wanted = @(("$($Item.Variables.allowedToJoinGroups)" -split ',').ForEach({ $_.Trim() }).Where({ $_ }) | Select-Object -Unique)
    if ($Wanted.Count -eq 0) { return @{ Current = $null; NoDataReason = 'Selected groups is chosen but no groups are configured'; ConfigError = $true } }

    $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
    if ($Groups.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Groups')) { return @{ Current = $null; NoDataReason = 'the groups cache could not be collected for this tenant' } }
    $ById = @{}
    $IdsByName = @{}
    foreach ($Group in $Groups) {
        if (-not $Group.id) { continue }
        $ById["$($Group.id)"] = $Group
        $Name = "$($Group.displayName)".Trim()
        if (-not $IdsByName.ContainsKey($Name)) { $IdsByName[$Name] = [System.Collections.Generic.List[string]]::new() }
        $IdsByName[$Name].Add("$($Group.id)")
    }

    $Resolved = [System.Collections.Generic.List[string]]::new()
    $Problems = foreach ($Entry in $Wanted) {
        if ($ById.ContainsKey($Entry)) { $Resolved.Add("$($ById[$Entry].id)"); continue }
        $Found = $IdsByName[$Entry]
        if (-not $Found) { "'$Entry' was not found" }
        elseif ($Found.Count -gt 1) { "'$Entry' matches $($Found.Count) groups, use its ID instead" }
        else { $Resolved.Add($Found[0]) }
    }
    if ($Problems) { return @{ Current = $null; NoDataReason = "Selected groups: $($Problems -join '; ')"; ConfigError = $true } }

    $Format = { param($Ids) (@($Ids) | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object { '{0} ({1})' -f ($ById["$_"].displayName ?? 'unknown group'), $_ }) -join ', ' }
    $Current | Add-Member -NotePropertyName 'allowedToJoinGroups' -NotePropertyValue (& $Format $Policy.azureADJoin.allowedToJoin.groups)
    # Carried for the executor, which writes the ids the names resolved to
    $Current | Add-Member -NotePropertyName 'allowedToJoinGroupIds' -NotePropertyValue @($Resolved | Sort-Object -Unique)
    @{
        Expected = [PSCustomObject]@{ allowedToJoin = $JoinType; allowedToJoinGroups = (& $Format $Resolved) }
        Current  = $Current
    }
}

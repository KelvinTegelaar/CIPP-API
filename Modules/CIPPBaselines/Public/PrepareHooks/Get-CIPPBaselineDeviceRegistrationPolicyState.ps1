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

    $Policy = @(@(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'DeviceRegistrationPolicy').Where({ $_ })) | Select-Object -First 1
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

    # Selected users and groups: comma separated names, UPNs or ids; a list variable arrives here already joined with commas.
    # A blank list expresses no opinion: it is neither graded nor written.
    $WantedGroups = @(("$($Item.Variables.allowedToJoinGroups)" -split ',').ForEach({ $_.Trim() }).Where({ $_ }) | Select-Object -Unique)
    $WantedUsers = @(("$($Item.Variables.allowedToJoinUsers)" -split ',').ForEach({ $_.Trim() }).Where({ $_ }) | Select-Object -Unique)
    if ($WantedGroups.Count -eq 0 -and $WantedUsers.Count -eq 0) { return @{ Current = $null; NoDataReason = 'Selected users and groups is chosen but no users or groups are configured'; ConfigError = $true } }
    $Join = $Policy.azureADJoin.allowedToJoin
    $Expected = [ordered]@{ allowedToJoin = $JoinType }
    $Carried = [ordered]@{}
    $Problems = [System.Collections.Generic.List[string]]::new()

    if ($WantedGroups.Count -gt 0) {
        $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups' -Fields 'displayName', 'id')
        if ($Groups.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Groups')) { return @{ Current = $null; NoDataReason = 'the groups cache could not be collected for this tenant' } }
        $GroupById = @{}
        $GroupIdsByName = @{}
        foreach ($Group in $Groups) {
            if (-not $Group.id) { continue }
            $GroupById["$($Group.id)"] = $Group
            $Name = "$($Group.displayName)".Trim()
            if (-not $GroupIdsByName.ContainsKey($Name)) { $GroupIdsByName[$Name] = [System.Collections.Generic.List[string]]::new() }
            $GroupIdsByName[$Name].Add("$($Group.id)")
        }
        $Resolved = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in $WantedGroups) {
            if ($GroupById.ContainsKey($Entry)) { $Resolved.Add("$($GroupById[$Entry].id)"); continue }
            $Found = $GroupIdsByName[$Entry]
            if (-not $Found) { $Problems.Add("group '$Entry' was not found") }
            elseif ($Found.Count -gt 1) { $Problems.Add("group '$Entry' matches $($Found.Count) groups, use its ID instead") }
            else { $Resolved.Add($Found[0]) }
        }
        $FormatGroups = { param($Ids) (@($Ids) | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object { '{0} ({1})' -f ($GroupById["$_"].displayName ?? 'unknown group'), $_ }) -join ', ' }
        $Expected.allowedToJoinGroups = & $FormatGroups $Resolved
        $Carried.allowedToJoinGroups = & $FormatGroups $Join.groups
        # Carried for the executor, which writes the ids the names resolved to
        $Carried.allowedToJoinGroupIds = @($Resolved | Sort-Object -Unique)
    }

    if ($WantedUsers.Count -gt 0) {
        $Users = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'userPrincipalName')
        if ($Users.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Users')) { return @{ Current = $null; NoDataReason = 'the users cache could not be collected for this tenant' } }
        $UserById = @{}
        $UserIdByUpn = @{}
        foreach ($User in $Users) {
            if (-not $User.id) { continue }
            $UserById["$($User.id)"] = $User
            if ($User.userPrincipalName) { $UserIdByUpn["$($User.userPrincipalName)"] = "$($User.id)" }
        }
        $Resolved = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in $WantedUsers) {
            $Id = if ($UserById.ContainsKey($Entry)) { "$($UserById[$Entry].id)" } else { $UserIdByUpn[$Entry] }
            if ($Id) { $Resolved.Add($Id) } else { $Problems.Add("user '$Entry' was not found") }
        }
        $FormatUsers = { param($Ids) (@($Ids) | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object { '{0} ({1})' -f ($UserById["$_"].userPrincipalName ?? 'unknown user'), $_ }) -join ', ' }
        $Expected.allowedToJoinUsers = & $FormatUsers $Resolved
        $Carried.allowedToJoinUsers = & $FormatUsers $Join.users
        $Carried.allowedToJoinUserIds = @($Resolved | Sort-Object -Unique)
    }

    if ($Problems.Count -gt 0) { return @{ Current = $null; NoDataReason = "Selected users and groups: $($Problems -join '; ')"; ConfigError = $true } }
    $Current | Add-Member -NotePropertyMembers $Carried
    @{
        Expected = [PSCustomObject]$Expected
        Current  = $Current
    }
}

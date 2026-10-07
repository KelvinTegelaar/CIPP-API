function Get-CIPPBaselineDisableM365GroupUsersState {
    <#
    .SYNOPSIS
        Prepare hook for DisableM365GroupUsers: is user-driven M365 group creation off.
    .DESCRIPTION
        Grades EnableGroupCreation on the Group.Unified directory setting, plus - only when
        an allowed group is configured - whether GroupCreationAllowedGroupId points at that
        group. The group resolves by display name from the Groups cache, since ids differ
        per tenant. A configured name that resolves to nothing grades as drift so it
        surfaces, exactly as the classic decided.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Settings = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Settings')
    if ($Settings.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Settings')) {
        return @{ Current = $null }
    }

    $GroupSetting = @($Settings | Where-Object { "$($_.displayName)" -eq 'Group.Unified' }) | Select-Object -First 1
    $ValueOf = { param($Name) "$((@($GroupSetting.values) | Where-Object { $_.name -eq $Name }).value)" }

    $AllowedGroupName = "$($Item.Variables.AllowedGroupName)"
    $DesiredGroupId = $null
    if (-not [string]::IsNullOrWhiteSpace($AllowedGroupName)) {
        $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
        $DesiredGroupId = "$((@($Groups | Where-Object { "$($_.displayName)" -eq $AllowedGroupName }) | Select-Object -First 1).id)"
    }

    $Expected = [PSCustomObject]@{ groupCreationDisabled = $true }
    $Current = [PSCustomObject]@{
        groupCreationDisabled = [bool]($GroupSetting -and (& $ValueOf 'EnableGroupCreation') -eq 'false')
    }
    if (-not [string]::IsNullOrWhiteSpace($AllowedGroupName)) {
        $Expected | Add-Member -NotePropertyName 'allowedGroupCorrect' -NotePropertyValue $true
        $Current | Add-Member -NotePropertyName 'allowedGroupCorrect' -NotePropertyValue ([bool](
                -not [string]::IsNullOrWhiteSpace($DesiredGroupId) -and (& $ValueOf 'GroupCreationAllowedGroupId') -eq $DesiredGroupId))
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'settingId' -NotePropertyValue "$($GroupSetting.id)"
    $Current | Add-Member -NotePropertyName 'resolvedGroupId' -NotePropertyValue $DesiredGroupId

    @{ Expected = $Expected; Current = $Current }
}

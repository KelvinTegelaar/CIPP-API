function Get-CIPPBaselineM365GroupGuestSettingsState {
    <#
    .SYNOPSIS
        Prepare hook for M365GroupGuestSettings: the guest values on the Group.Unified
        directory setting.
    .DESCRIPTION
        Grades AllowGuestsToBeGroupOwner and AllowGuestsToAccessGroups on the Group.Unified
        setting (template 62375ab9-6b52-47ed-826b-58e47e0e304b). Directory setting values
        are STRINGS on the wire, so both sides grade as lower-case strings. A tenant with
        no Group.Unified object grades every value against empty - not configured is drift,
        and remediation instantiates the object.
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

    $V = $Item.Variables
    $AsFlag = { param($Value) if ($Value -eq $true -or "$Value" -eq 'True') { 'true' } else { 'false' } }

    $Existing = @($Settings | Where-Object { "$($_.displayName)" -eq 'Group.Unified' }) | Select-Object -First 1
    $ValueOf = { param($Name) "$((@($Existing.values) | Where-Object { $_.name -eq $Name }).value)".ToLower() }

    $Current = [PSCustomObject]@{
        allowGuestsToBeGroupOwner = $(if ($Existing) { & $ValueOf 'AllowGuestsToBeGroupOwner' } else { '' })
        allowGuestsToAccessGroups = $(if ($Existing) { & $ValueOf 'AllowGuestsToAccessGroups' } else { '' })
    }
    $Current | Add-Member -NotePropertyName 'settingId' -NotePropertyValue "$($Existing.id)"

    @{
        Expected = [PSCustomObject]@{
            allowGuestsToBeGroupOwner = & $AsFlag $V.AllowGuestsToBeGroupOwner
            allowGuestsToAccessGroups = & $AsFlag $V.AllowGuestsToAccessGroups
        }
        Current  = $Current
    }
}

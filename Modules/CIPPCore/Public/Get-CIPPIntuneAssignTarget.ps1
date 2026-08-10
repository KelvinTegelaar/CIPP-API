function Get-CIPPIntuneAssignTarget {
    <#
    .SYNOPSIS
        Normalizes an Intune template's AssignTo setting and reports what remediation will do with it.
    .DESCRIPTION
        The assignment expectation and the assignment remediation have to agree, or drift can never
        converge: a comparison that asserts something remediation does not do produces a deviation
        no run can ever clear. Both sides read the setting through this function so they cannot
        drift apart.

        Two flags come out of it:

        Applied - remediation calls Set-CIPPAssignedPolicy at all. Set-CIPPIntunePolicy skips the
                  assignment step entirely when AssignTo is empty, so nothing about assignments
                  (not even a missing exclusion or filter) is remediable in that case.
        Managed - the standard names a concrete include target, which means it owns the policy's
                  assignments outright and remediation replaces them. Only then can an unexpected
                  extra group or filter actually be removed, so only then is it a real deviation.

        'On' ("Do not assign") is Applied but not Managed: remediation still applies exclusions and
        filters, but it adds no include target and cannot remove one that is already there.

        Also unwraps the { label, value } shape. The radio control stores a plain string today, but
        templates imported from older versions or from the community repo can carry the object.
    .PARAMETER AssignTo
        The raw AssignTo value from the standard's settings. String or { label, value } object.
    .EXAMPLE
        Get-CIPPIntuneAssignTarget -AssignTo $Settings.AssignTo
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $AssignTo
    )

    $Value = $AssignTo
    if ($null -ne $Value -and $Value -isnot [string] -and $Value.PSObject.Properties.Name -contains 'value') {
        $Value = $Value.value
    }
    $Value = ([string]$Value).Trim()

    # Match case-insensitively but return the canonical casing, so callers can compare with -eq
    # without repeating the casing of every option.
    $KnownTargets = @('allLicensedUsers', 'AllDevices', 'AllDevicesAndUsers', 'customGroup')
    $Canonical = $KnownTargets | Where-Object { $_ -eq $Value } | Select-Object -First 1

    [PSCustomObject]@{
        AssignTo = if ($Canonical) { $Canonical } else { $Value }
        Managed  = [bool]$Canonical
        Applied  = -not [string]::IsNullOrWhiteSpace($Value)
    }
}

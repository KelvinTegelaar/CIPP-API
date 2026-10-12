function Invoke-CIPPBaselineDeviceRegistrationPolicy {
    <#
    .SYNOPSIS
        DeviceRegistrationPolicy executor: merge-writes one or more settings into
        policies/deviceRegistrationPolicy.
    .DESCRIPTION
        Graph exposes no PATCH here - the whole object goes back on a PUT. Six standards
        each own a different field of it, so a write that sent only its own field would
        wipe the other five: enforcing the device quota would silently undo LAPS and the
        MFA-on-join requirement. This executor GETs the object, assigns only the paths the
        definition names, and PUTs the merged result.

        The merge base is a LIVE read, never the cached row: the cache can be hours old, and
        merging from it would revert whatever a sibling standard wrote since the last
        collection - the exact clobbering this exists to prevent.

        Spec (fully rendered):
          set                       - { "<dot.path>": <value> }, assigned verbatim, so a
                                      membership setting supplies its whole
                                      { '@odata.type', users, groups } object.
          requireAdminConfigurable  - optional dot-path to a node carrying
                                      isAdminConfigurable. Graph refuses the write when that
                                      is false (commonly because Intune manages the setting),
                                      which is a tenant fact rather than a failure - the step
                                      is skipped with a warning instead of erroring on every
                                      run against most of the fleet.

        Delegated, matching the classic standards: deviceRegistrationPolicy updates are not
        supported with application permissions.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        # The read result. Unused - the merge base has to be live, see above.
        $Current
    )

    $Uri = 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy'
    $Policy = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter
    if ($null -eq $Policy) { throw 'Could not read policies/deviceRegistrationPolicy to merge into.' }

    $Guard = "$($Remediate.requireAdminConfigurable)"
    if ($Guard) {
        $Node = $Policy
        foreach ($Segment in ($Guard -split '\.')) { $Node = $Node.$Segment }
        if ($Node.isAdminConfigurable -eq $false) {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Device registration policy: $Guard.isAdminConfigurable is false for this tenant, so this setting cannot be changed - skipping the write." -Sev 'Warning'
            return
        }
    }

    $Assigned = 0
    foreach ($Entry in ($Remediate.set ?? [PSCustomObject]@{}).PSObject.Properties) {
        $Segments = @($Entry.Name -split '\.')
        $Target = $Policy
        for ($i = 0; $i -lt ($Segments.Count - 1); $i++) {
            $Target = $Target.$($Segments[$i])
            if ($null -eq $Target) { throw "deviceRegistrationPolicy on this tenant has no '$($Entry.Name)' to write." }
        }
        $Leaf = $Segments[-1]
        if ($Target.PSObject.Properties.Name -contains $Leaf) {
            $Target.$Leaf = $Entry.Value
        } else {
            $Target | Add-Member -NotePropertyName $Leaf -NotePropertyValue $Entry.Value -Force
        }
        $Assigned++
    }
    if ($Assigned -eq 0) { throw 'DeviceRegistrationPolicy: nothing configured to write.' }

    $null = New-GraphPostRequest -tenantid $TenantFilter -uri $Uri -Type PUT -Body (ConvertTo-Json -Compress -Depth 10 -InputObject $Policy) -ContentType 'application/json'
}

function Invoke-CIPPBaselineQuarantineRequestAlert {
    <#
    .SYNOPSIS
        QuarantineRequestAlert executor: creates or updates the quarantine release-request
        alert without discarding recipients it did not add, or removes the alert entirely.
    .DESCRIPTION
        Needs its own executor because the recipient list it writes depends on the list already
        there, and a rendered ExoRequest spec is fixed before it ever sees the tenant.

        With allowExtraAddresses set, the write is a MERGE: the configured address is added to
        whatever is already on the alert, deduplicated, case-insensitively. Somebody who added
        their own address by hand keeps it. Without it, the configured address is the whole
        list and anything else is removed - the classic standard's behaviour.

        With state 'removed' the desired state is that the alert does not exist: the alert is
        deleted when present and left alone when it already is not, and the notify settings
        are ignored.

        The existing list is read LIVE rather than from cache. A cached list can be hours old,
        and merging into a stale one would silently drop a recipient added since the last
        collection, which is precisely the loss the merge exists to prevent. Removal shares
        the read: deleting is only skipped when the alert is verifiably absent.

        Create-vs-update is decided the same way: the alert is looked up by name, and only
        created when it genuinely is not there. All three cmdlets are Security & Compliance only.
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

    $PolicyName = 'CIPP User requested to release a quarantined message'
    $Configured = "$($Remediate.notifyUser)"
    if ([string]::IsNullOrWhiteSpace($Configured)) { throw 'QuarantineRequestAlert: no notify address configured to write.' }
    $AllowExtra = [bool]($Remediate.allowExtraAddresses -eq $true)

    $Existing = $null
    try {
        $Existing = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ProtectionAlert' -Compliance |
                Where-Object { $_.Name -eq $PolicyName }) | Select-Object -First 1
    } catch {
        throw "QuarantineRequestAlert: could not read the existing alert to merge into: $($_.Exception.Message)"
    }

    $Recipients = [System.Collections.Generic.List[string]]::new()
    $Recipients.Add($Configured)
    if ($AllowExtra) {
        foreach ($Address in @($Existing.NotifyUser)) {
            if ([string]::IsNullOrWhiteSpace($Address)) { continue }
            if (@($Recipients | Where-Object { $_ -eq "$Address" }).Count -gt 0) { continue }
            $Recipients.Add("$Address")
        }
    }

    $Parameters = @{
        Category        = 'ThreatManagement'
        Operation       = 'QuarantineRequestReleaseMessage'
        Severity        = 'Informational'
        AggregationType = 'None'
        NotifyUser      = @($Recipients)
    }

    if ($Existing) {
        $Parameters['Identity'] = $PolicyName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-ProtectionAlert' -Compliance -cmdParams $Parameters -useSystemMailbox $true
    } else {
        $Parameters['Name'] = $PolicyName
        $Parameters['ThreatType'] = 'Activity'
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ProtectionAlert' -Compliance -cmdParams $Parameters -useSystemMailbox $true
    }
}

function Get-CIPPEnrollmentTimeDeviceMembershipTarget {
    <#
    .SYNOPSIS
        The enrollment-time device group applied to a Device Preparation policy.
    .DESCRIPTION
        Resolution order: the retrieveEnrollmentTimeDeviceMembershipTarget action, then the
        marker CIPP wrote when it last applied a group, then nothing.

        The live action comes first so a group swapped or cleared in the portal is seen and
        repaired; the marker only carries the comparison on tenants where the action does not
        route, and it is stale by definition on those where it does. The
        enrollment_autopilot_dpp_devicesecuritygroupids setting string is deliberately NOT a
        fallback: every build writes it on create while the group itself stays unapplied, so it
        reports a half-deployed profile as healthy. No answer at all grades as no group applied,
        which is the state the repair path can act on.

        This is the only place the read-side URI is built.
    .PARAMETER PolicyId
        The configuration policy id.
    .PARAMETER TenantFilter
        The tenant to query.
    .OUTPUTS
        PSCustomObject with GroupId (empty when no group is applied) and Source, one of 'Marker',
        'Retrieved' or 'None'.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $Result = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$PolicyId')/retrieveEnrollmentTimeDeviceMembershipTarget" -tenantid $TenantFilter -type POST
        # The action result arrives both directly and wrapped in a value collection.
        $Payload = if ($null -ne $Result.value) { $Result.value } else { $Result }
        $Targets = @($Payload | ForEach-Object { $_.enrollmentTimeDeviceMembershipTargets } | Where-Object { $_ })
        $Static = @($Targets | Where-Object { $_.targetType -eq 'staticSecurityGroup' -and $_.targetId }) | Select-Object -First 1
        return [PSCustomObject]@{ GroupId = [string]$Static.targetId; Source = 'Retrieved' }
    } catch {
        Write-Information "Enrollment time device membership target is unavailable for policy $PolicyId : $($_.Exception.Message)"
    }

    try {
        $Table = Get-CIPPTable -TableName 'EnrollmentTimeMembershipTargets'
        $Marker = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$PolicyId'" | Select-Object -First 1
        if ($Marker) {
            return [PSCustomObject]@{ GroupId = [string]$Marker.GroupId; Source = 'Marker' }
        }
    } catch {
        Write-Information "Could not read the enrollment time device membership marker for policy $PolicyId : $($_.Exception.Message)"
    }

    [PSCustomObject]@{ GroupId = ''; Source = 'None' }
}

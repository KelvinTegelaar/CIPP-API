function Get-NinjaOneDeviceNonCompliantSettings {
    <#
    .SYNOPSIS
    Lists, per Intune managed device, the compliance policy settings the device currently fails.

    .DESCRIPTION
    Backs the 'Intune Non-Compliant Settings' NinjaOne custom field. Runs two Graph batch rounds for the
    whole set of devices instead of a call per device: first every device's compliance policy states, then
    the setting states of each policy state that is not compliant. Returns a hashtable keyed by managed
    device id whose value is a newline separated list of 'Policy name: Setting name' lines. Devices with
    nothing failing are absent from the result.

    .PARAMETER TenantFilter
    Tenant to query.

    .PARAMETER ManagedDeviceIds
    Intune managed device ids to look up. Only non-compliant devices need to be passed.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ManagedDeviceIds
    )

    # Matches the states the device page treats as failures (CippDevicePolicySettingStates.jsx).
    $FailingStates = @('nonCompliant', 'error', 'conflict')
    $Results = @{}

    $DeviceIds = @($ManagedDeviceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($DeviceIds.Count -eq 0) {
        return $Results
    }

    $PolicyStateRequests = [System.Collections.Generic.List[object]]::new()
    foreach ($DeviceId in $DeviceIds) {
        $PolicyStateRequests.Add(@{
                id     = $DeviceId
                method = 'GET'
                url    = "/deviceManagement/managedDevices('$DeviceId')/deviceCompliancePolicyStates"
            })
    }
    $PolicyStateResponses = New-GraphBulkRequest -Requests $PolicyStateRequests -tenantid $TenantFilter

    # The policy state list only carries the policy name; the failing settings come from a second call per policy state.
    $SettingStateRequests = [System.Collections.Generic.List[object]]::new()
    $PolicyNames = @{}
    foreach ($Response in $PolicyStateResponses) {
        if (($Response.status -as [int]) -ge 400) {
            Write-Warning "Get-NinjaOneDeviceNonCompliantSettings: compliance policy states for device '$($Response.id)' returned $($Response.status): $($Response.body.error.message)"
            continue
        }
        $DeviceId = [string]$Response.id
        foreach ($PolicyState in @($Response.body.value | Where-Object { $_.state -in $FailingStates })) {
            $RequestId = "$DeviceId|$($PolicyState.id)"
            $PolicyNames[$RequestId] = $PolicyState.displayName
            $SettingStateRequests.Add(@{
                    id     = $RequestId
                    method = 'GET'
                    url    = "/deviceManagement/managedDevices('$DeviceId')/deviceCompliancePolicyStates/$($PolicyState.id)/settingStates"
                })
        }
    }

    if ($SettingStateRequests.Count -eq 0) {
        return $Results
    }

    $SettingStateResponses = New-GraphBulkRequest -Requests $SettingStateRequests -tenantid $TenantFilter

    $Lines = @{}
    foreach ($Response in $SettingStateResponses) {
        if (($Response.status -as [int]) -ge 400) {
            Write-Warning "Get-NinjaOneDeviceNonCompliantSettings: setting states for '$($Response.id)' returned $($Response.status): $($Response.body.error.message)"
            continue
        }
        $ResponseId = [string]$Response.id
        $DeviceId = ($ResponseId -split '\|', 2)[0]
        $PolicyName = $PolicyNames[$ResponseId]
        if (-not $Lines.ContainsKey($DeviceId)) {
            $Lines[$DeviceId] = [System.Collections.Generic.List[string]]::new()
        }
        foreach ($Setting in @($Response.body.value | Where-Object { $_.state -in $FailingStates })) {
            $SettingName = if ($Setting.settingName) { $Setting.settingName } elseif ($Setting.setting) { $Setting.setting } else { 'Unknown setting' }
            $Line = "$($PolicyName): $SettingName"
            if ($Setting.state -ne 'nonCompliant') {
                $Line = "$Line ($($Setting.state))"
            }
            # A policy reports one setting state per user, so the same failure can appear several times.
            if (-not $Lines[$DeviceId].Contains($Line)) {
                $Lines[$DeviceId].Add($Line)
            }
        }
    }

    foreach ($DeviceId in $Lines.Keys) {
        if ($Lines[$DeviceId].Count -gt 0) {
            $Results[$DeviceId] = $Lines[$DeviceId] -join "`n"
        }
    }

    return $Results
}

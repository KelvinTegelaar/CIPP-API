function Invoke-CIPPStandardStaleEntraDevices {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) StaleEntraDevices
    .SYNOPSIS
        (Label) Cleanup stale Entra devices
    .DESCRIPTION
        (Helptext) Cleans up Entra devices that have not connected/signed in for the specified number of days. Remediation first disables stale enabled devices and, on a later run, deletes stale devices that are already disabled. Hybrid-joined, Intune-managed and Autopilot devices are skipped. Deleting a device permanently removes any BitLocker recovery keys stored on it.
        (DocsDescription) Cleans up Entra devices that have not connected/signed in for the specified number of days. Remediation first disables stale enabled devices once they pass the disable threshold, and later deletes devices that are already disabled once they have been inactive for the disable threshold plus the configured grace delta (deletion age = disable threshold + grace days). The disable-before-delete grace period is further guaranteed by never deleting a device in the same pass it was disabled. Hybrid-joined (on-premises synced), Intune-managed/compliant, and system-managed Autopilot devices are excluded, in line with the [Microsoft guidance](https://learn.microsoft.com/en-us/entra/identity/devices/manage-stale-devices). **Warning:** deleting a device permanently removes any BitLocker recovery keys stored on that device object.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "Essential 8 (1501)"
            "NIST CSF 2.0 (ID.AM-08)"
            "NIST CSF 2.0 (PR.PS-03)"
        EXECUTIVETEXT
            Automatically identifies and removes inactive devices that haven't connected to company systems for a specified period, reducing security risks from abandoned or lost devices. This maintains a clean device inventory and prevents potential unauthorized access through dormant device registrations.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.StaleEntraDevices.deviceAgeThreshold","label":"Days before stale (disables the device after this many days of inactivity, minimum 30)","required":true,"defaultValue":90,"validators":{"min":{"value":30,"message":"Minimum value is 30"}}}
            {"type":"number","name":"standards.StaleEntraDevices.deviceDeleteThreshold","label":"Grace days after disable before deletion (0 = never delete). Devices are deleted once inactive for the disable threshold plus this many additional days.","defaultValue":0,"validators":{"min":{"value":0,"message":"Minimum value is 0"}}}
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            High Impact
        ADDEDDATE
            2025-01-19
        POWERSHELLEQUIVALENT
            Remove-MgDevice, Update-MgDevice or Graph API
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    # Safety guard: never run below the supported minimum. A blank or low threshold would otherwise treat
    # every device with any sign-in as stale and disable the entire fleet.
    $DisableThreshold = if ([string]::IsNullOrWhiteSpace([string]$Settings.deviceAgeThreshold)) { 0 } else { [int]$Settings.deviceAgeThreshold }
    if ($DisableThreshold -lt 30) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "StaleEntraDevices: deviceAgeThreshold ($DisableThreshold) is below the minimum of 30 days. Skipping run to prevent mass device changes." -Sev Error
        return
    }

    # deviceDeleteThreshold is a delta (grace days) added on top of the disable threshold, so the effective
    # delete age is always greater than the disable age - deletion can never overtake disable by construction.
    $DeleteDelta = if ([string]::IsNullOrWhiteSpace([string]$Settings.deviceDeleteThreshold)) { 0 } else { [int]$Settings.deviceDeleteThreshold }
    if ($DeleteDelta -lt 0) { $DeleteDelta = 0 }
    $DeleteEnabled = $DeleteDelta -gt 0
    $DeleteAge = $DisableThreshold + $DeleteDelta

    try {
        $AllDevices = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/devices?$select=id,displayName,approximateLastSignInDateTime,accountEnabled,enrollmentProfileName,operatingSystem,managementType,profileType,onPremisesSyncEnabled,isManaged,isCompliant,physicalIds' -tenantid $Tenant | Where-Object { $null -ne $_.approximateLastSignInDateTime }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the StaleEntraDevices state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $DisableDate = (Get-Date).AddDays(-$DisableThreshold)
    $DeleteDate = (Get-Date).AddDays(-$DeleteAge)

    # Devices are excluded from remediation when they are hybrid-joined (managed on-premises via Entra Connect),
    # Intune managed/compliant (should be retired in Intune first), or system-managed Autopilot devices
    # (identified by a ZTDID in physicalIds - deleting these breaks re-provisioning and cannot be undone).
    $SafetyFilter = {
        $_.onPremisesSyncEnabled -ne $true -and
        $_.isManaged -ne $true -and
        $_.isCompliant -ne $true -and
        (@($_.physicalIds) -join ' ') -notmatch '\[ZTDID\]'
    }

    # Compute the working sets from the current device state. Re-run after remediation so alert/report reflect
    # the post-remediation state. Delete only targets devices that are ALREADY disabled and stale beyond the
    # delete threshold; devices disabled in this same run are not deleted until a later run (grace period).
    # Dot-sourced so assignments land in this function's scope (no module-level state persists between runs).
    $ComputeSets = {
        $StaleDevices = @($AllDevices | Where-Object { $_.approximateLastSignInDateTime -lt $DisableDate })
        $RemediationEligibleStaleDevices = @($StaleDevices | Where-Object $SafetyFilter)
        $DevicesToDisable = @($RemediationEligibleStaleDevices | Where-Object { $_.accountEnabled -eq $true })
        if ($DeleteEnabled) {
            # Every safety-eligible device inactive beyond the delete age meets the delete threshold (surfaced in reports).
            $DevicesMeetingDeleteThreshold = @($AllDevices | Where-Object { $_.approximateLastSignInDateTime -lt $DeleteDate } | Where-Object $SafetyFilter)
            # Only those already disabled are actually deleted this run; enabled ones are disabled first and deleted later.
            $DevicesToDelete = @($DevicesMeetingDeleteThreshold | Where-Object { $_.accountEnabled -ne $true })
        } else {
            $DevicesMeetingDeleteThreshold = @()
            $DevicesToDelete = @()
        }
    }
    . $ComputeSets

    if ($Settings.remediate -eq $true) {
        $DeletedDeviceIds = [System.Collections.Generic.List[string]]::new()
        $DisabledCount = 0
        $DeletedCount = 0
        $FailedCount = 0

        if ($DevicesToDisable.Count -gt 0) {
            $DisableRequests = [System.Collections.Generic.List[hashtable]]::new()
            $DisableMap = @{}
            $RequestId = 0

            foreach ($Device in $DevicesToDisable) {
                $CurrentId = $RequestId++
                $DisableMap[$CurrentId] = $Device
                $DisableRequests.Add(@{
                        id      = $CurrentId
                        method  = 'PATCH'
                        url     = "devices/$($Device.id)"
                        body    = @{ accountEnabled = $false }
                        headers = @{
                            'Content-Type' = 'application/json'
                        }
                    })
            }

            try {
                $DisableResults = New-GraphBulkRequest -tenantid $Tenant -Version 'v1.0' -Requests @($DisableRequests)
                foreach ($Result in $DisableResults) {
                    $Device = $DisableMap[[int]$Result.id]
                    if ($null -eq $Device) {
                        continue
                    }

                    if ($Result.status -eq 200 -or $Result.status -eq 204) {
                        $DisabledCount++
                        $Device.accountEnabled = $false
                    } else {
                        $FailedCount++
                        $ErrorMessage = if ($Result.body.error.message) { $Result.body.error.message } else { "Unknown error (Status: $($Result.status))" }
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not disable stale device $($Device.displayName) ($($Device.id)). Error: $ErrorMessage" -Sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $FailedCount += $DevicesToDisable.Count
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to process bulk disable stale devices request. Error: $ErrorMessage" -Sev Error
            }
        }

        if ($DevicesToDelete.Count -gt 0) {
            $DeleteRequests = [System.Collections.Generic.List[hashtable]]::new()
            $DeleteMap = @{}
            $RequestId = 0

            foreach ($Device in $DevicesToDelete) {
                $CurrentId = $RequestId++
                $DeleteMap[$CurrentId] = $Device
                $DeleteRequests.Add(@{
                        id     = $CurrentId
                        method = 'DELETE'
                        url    = "devices/$($Device.id)"
                    })
            }

            try {
                $DeleteResults = New-GraphBulkRequest -tenantid $Tenant -Version 'v1.0' -Requests @($DeleteRequests)
                foreach ($Result in $DeleteResults) {
                    $Device = $DeleteMap[[int]$Result.id]
                    if ($null -eq $Device) {
                        continue
                    }

                    if ($Result.status -eq 200 -or $Result.status -eq 204) {
                        $DeletedCount++
                        $null = $DeletedDeviceIds.Add([string]$Device.id)
                    } else {
                        $FailedCount++
                        $ErrorMessage = if ($Result.body.error.message) { $Result.body.error.message } else { "Unknown error (Status: $($Result.status))" }
                        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not delete stale eligible device $($Device.displayName) ($($Device.id)). Error: $ErrorMessage" -Sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $FailedCount += $DevicesToDelete.Count
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to process bulk delete stale devices request. Error: $ErrorMessage" -Sev Error
            }
        }

        # Drop deleted devices, then recompute the working sets so alert/report reflect the post-remediation state.
        if ($DeletedDeviceIds.Count -gt 0) {
            $AllDevices = @($AllDevices | Where-Object { $_.id -notin $DeletedDeviceIds })
        }
        . $ComputeSets

        # Only log when the standard actually acted; skipped devices alone never generate output.
        if ($DisabledCount -gt 0 -or $DeletedCount -gt 0 -or $FailedCount -gt 0) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "StaleEntraDevices remediation completed. Disabled: $DisabledCount. Deleted: $DeletedCount. Failed: $FailedCount." -Sev Info
        }

    }


    if ($Settings.alert -eq $true) {

        # Alert only on actionable devices. Skipped devices (hybrid-joined/Intune-managed/Autopilot) are
        # intentionally excluded so the alert never fires on stale devices this standard would never touch.
        if ($RemediationEligibleStaleDevices.Count -gt 0) {
            $AlertMessage = "$($RemediationEligibleStaleDevices.Count) stale devices requiring action found (to disable: $($DevicesToDisable.Count), meeting delete threshold: $($DevicesMeetingDeleteThreshold.Count))."
            Write-StandardsAlert -message $AlertMessage -object $RemediationEligibleStaleDevices -tenant $Tenant -standardName 'StaleEntraDevices' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No stale devices requiring action found' -sev Info
        }
    }


    if ($Settings.report -eq $true) {

        # Report only on actionable devices; skipped devices (hybrid-joined/Intune-managed/Autopilot) are excluded.
        if ($RemediationEligibleStaleDevices.Count -gt 0) {
            $StaleReport = ConvertTo-Json -InputObject ($RemediationEligibleStaleDevices | Select-Object -Property displayName, id, approximateLastSignInDateTime, accountEnabled, enrollmentProfileName, operatingSystem, managementType, profileType) -Depth 10 -Compress
            Add-CIPPBPAField -FieldName 'StaleEntraDevices' -FieldValue $StaleReport -StoreAs json -Tenant $Tenant
        } else {
            Add-CIPPBPAField -FieldName 'StaleEntraDevices' -FieldValue $true -StoreAs bool -Tenant $Tenant
        }

        if ($DevicesToDisable.Count -gt 0) {
            $EligibleToDisableFieldValue = $DevicesToDisable | Select-Object -Property displayName, id, approximateLastSignInDateTime, accountEnabled, enrollmentProfileName, operatingSystem, managementType, profileType
        }
        if ($DeleteEnabled -and $DevicesMeetingDeleteThreshold.Count -gt 0) {
            $MeetingDeleteThresholdFieldValue = $DevicesMeetingDeleteThreshold | Select-Object -Property displayName, id, approximateLastSignInDateTime, accountEnabled, enrollmentProfileName, operatingSystem, managementType, profileType
        }

        $CurrentValue = @{
            EligibleDevicesToDisable      = ($EligibleToDisableFieldValue ? @($EligibleToDisableFieldValue) :@())
            DevicesMeetingDeleteThreshold = if ($DeleteEnabled) { ($MeetingDeleteThresholdFieldValue ? @($MeetingDeleteThresholdFieldValue) :@()) } else { 'Deletion disabled' }
        }
        $ExpectedValue = @{
            EligibleDevicesToDisable      = @()
            DevicesMeetingDeleteThreshold = if ($DeleteEnabled) { @() } else { 'Deletion disabled' }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.StaleEntraDevices' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}

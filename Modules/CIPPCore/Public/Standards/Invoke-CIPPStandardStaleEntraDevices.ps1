function Invoke-CIPPStandardStaleEntraDevices {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) StaleEntraDevices
    .SYNOPSIS
        (Label) Cleanup stale Entra devices
    .DESCRIPTION
        (Helptext) Cleans up Entra devices that have not connected/signed in for the specified number of days. Remediation first disables stale enabled devices and later deletes stale already-disabled devices.
        (DocsDescription) Cleans up Entra devices that have not connected/signed in for the specified number of days. Remediation first disables stale enabled devices and later deletes stale already-disabled devices. More info can be found in the [Microsoft documentation](https://learn.microsoft.com/en-us/entra/identity/devices/manage-stale-devices)
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
            {"type":"number","name":"standards.StaleEntraDevices.deviceAgeThreshold","label":"Days before stale (Disables the device after this many days of inactivity)"}
            {"type":"number","name":"standards.StaleEntraDevices.deviceDeleteThreshold","label":"Days before stale devices are deleted (0 means devices will NOT be deleted)"}
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            High Impact
        ADDEDDATE
            2025-01-19
        POWERSHELLEQUIVALENT
            Remove-MgDevice, Update-MgDevice or Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $AllDevices = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/devices?$select=id,displayName,approximateLastSignInDateTime,accountEnabled,enrollmentProfileName,operatingSystem,managementType,profileType,onPremisesSyncEnabled,isManaged,isCompliant' -tenantid $Tenant | Where-Object { $null -ne $_.approximateLastSignInDateTime }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the StaleEntraDevices state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $Date = (Get-Date).AddDays( - [int]$Settings.deviceAgeThreshold)
    $DeleteThreshold = if ($null -eq $Settings.deviceDeleteThreshold) { 0 } else { [int]$Settings.deviceDeleteThreshold }
    $DeleteEnabled = $DeleteThreshold -gt 0
    $DeleteDate = (Get-Date).AddDays( - $DeleteThreshold)
    $StaleDevices = $AllDevices | Where-Object { $_.approximateLastSignInDateTime -lt $Date }
    $DeleteDevices = $AllDevices | Where-Object { $_.approximateLastSignInDateTime -lt $DeleteDate }

    $RemediationSkippedStaleDevices = @($StaleDevices | Where-Object { $_.onPremisesSyncEnabled -eq $true -or $_.isManaged -eq $true -or $_.isCompliant -eq $true })
    $RemediationEligibleStaleDevices = @($StaleDevices | Where-Object { $_.onPremisesSyncEnabled -ne $true -and $_.isManaged -ne $true -and $_.isCompliant -ne $true })
    $DeleteEligibleDevices = @($DeleteDevices | Where-Object { $_.onPremisesSyncEnabled -ne $true -and $_.isManaged -ne $true -and $_.isCompliant -ne $true })
    if (-not $DeleteEnabled) {
        $DevicesToDelete = @()
    } else {
        $DevicesToDelete = @($DeleteEligibleDevices | Where-Object { $_.accountEnabled -ne $true })
    }
    $DevicesToDisable = @($RemediationEligibleStaleDevices | Where-Object { $_.accountEnabled -eq $true })

    if ($Settings.remediate -eq $true) {
        $DeletedDeviceIds = [System.Collections.Generic.List[string]]::new()
        $SkippedCount = $RemediationSkippedStaleDevices.Count
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
                        id        = $CurrentId
                        method    = 'PATCH'
                        url       = "devices/$($Device.id)"
                        body      = @{ accountEnabled = $false }
                        headers   = @{
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
                        $DeleteDevice = $DeleteDevices | Where-Object { $_.id -eq $Device.id } | Select-Object -First 1
                        if ($DeleteDevice) {
                            $DeleteDevice.accountEnabled = $false
                        }
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

        $DeleteEligibleDevices = @($DeleteDevices | Where-Object { $_.onPremisesSyncEnabled -ne $true -and $_.isManaged -ne $true -and $_.isCompliant -ne $true })
        if (-not $DeleteEnabled) {
            $DevicesToDelete = @()
        } else {
            $DevicesToDelete = @($DeleteEligibleDevices | Where-Object { $_.accountEnabled -ne $true })
        }

        if ($DevicesToDelete.Count -gt 0) {
            $DeleteRequests = [System.Collections.Generic.List[hashtable]]::new()
            $DeleteMap = @{}
            $RequestId = 0

            foreach ($Device in $DevicesToDelete) {
                $CurrentId = $RequestId++
                $DeleteMap[$CurrentId] = $Device
                $DeleteRequests.Add(@{
                        id      = $CurrentId
                        method  = 'DELETE'
                        url     = "devices/$($Device.id)"
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

        if ($DeletedDeviceIds.Count -gt 0) {
            $StaleDevices = @($StaleDevices | Where-Object { $_.id -notin $DeletedDeviceIds })
            $DeleteDevices = @($DeleteDevices | Where-Object { $_.id -notin $DeletedDeviceIds })
        }

        $RemediationSkippedStaleDevices = @($StaleDevices | Where-Object { $_.onPremisesSyncEnabled -eq $true -or $_.isManaged -eq $true -or $_.isCompliant -eq $true })
        $RemediationEligibleStaleDevices = @($StaleDevices | Where-Object { $_.onPremisesSyncEnabled -ne $true -and $_.isManaged -ne $true -and $_.isCompliant -ne $true })
        $DeleteEligibleDevices = @($DeleteDevices | Where-Object { $_.onPremisesSyncEnabled -ne $true -and $_.isManaged -ne $true -and $_.isCompliant -ne $true })
        if (-not $DeleteEnabled) {
            $DevicesToDelete = @()
        } else {
            $DevicesToDelete = @($DeleteEligibleDevices | Where-Object { $_.accountEnabled -ne $true })
        }
        $DevicesToDisable = @($RemediationEligibleStaleDevices | Where-Object { $_.accountEnabled -eq $true })

        if ($DisabledCount -gt 0 -or $DeletedCount -gt 0 -or $FailedCount -gt 0 -or $SkippedCount -gt 0) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "StaleEntraDevices remediation completed. Disabled: $DisabledCount. Deleted: $DeletedCount. Failed: $FailedCount. Skipped: $SkippedCount (onPremisesSyncEnabled/isManaged/isCompliant)." -Sev Info
        }

    }


    if ($Settings.alert -eq $true) {

        if ($StaleDevices.Count -gt 0) {
            $AlertMessage = "$($StaleDevices.Count) stale devices found. Eligible for remediation: $($RemediationEligibleStaleDevices.Count) (disable: $($DevicesToDisable.Count), delete: $($DevicesToDelete.Count)). Skipped by safety checks: $($RemediationSkippedStaleDevices.Count)."
            Write-StandardsAlert -message $AlertMessage -object $StaleDevices -tenant $Tenant -standardName 'StaleEntraDevices' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No stale devices found' -sev Info
        }
    }


    if ($Settings.report -eq $true) {

        if ($StaleDevices.Count -gt 0) {
            $StaleReport = ConvertTo-Json -InputObject ($StaleDevices | Select-Object -Property displayName, id, approximateLastSignInDateTime, accountEnabled, enrollmentProfileName, operatingSystem, managementType, profileType) -Depth 10 -Compress
            Add-CIPPBPAField -FieldName 'StaleEntraDevices' -FieldValue $StaleReport -StoreAs json -Tenant $Tenant
        } else {
            Add-CIPPBPAField -FieldName 'StaleEntraDevices' -FieldValue $true -StoreAs bool -Tenant $Tenant
        }

        if ($DevicesToDisable.Count -gt 0) {
            $EligibleToDisableFieldValue = $DevicesToDisable | Select-Object -Property displayName, id, approximateLastSignInDateTime, accountEnabled, enrollmentProfileName, operatingSystem, managementType, profileType
        }
        if ($DeleteEnabled -and $DevicesToDelete.Count -gt 0) {
            $EligibleToDeleteFieldValue = $DevicesToDelete | Select-Object -Property displayName, id, approximateLastSignInDateTime, accountEnabled, enrollmentProfileName, operatingSystem, managementType, profileType
        }

        $CurrentValue = @{
            EligibleDevicesToDisable      = ($EligibleToDisableFieldValue ? @($EligibleToDisableFieldValue) :@())
            EligibleDevicesToDelete       = if ($DeleteEnabled) { ($EligibleToDeleteFieldValue ? @($EligibleToDeleteFieldValue) :@()) } else { 'Deletion disabled' }
        }
        $ExpectedValue = @{
            EligibleDevicesToDisable      = @()
            EligibleDevicesToDelete       = if ($DeleteEnabled) { @() } else { 'Deletion disabled' }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.StaleEntraDevices' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}

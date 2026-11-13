function Invoke-ListIntuneDeploymentStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists the per-device and per-user deployment status of one Intune app, policy or script, like the Device status and User status pages in Intune. Devices or Users is null when Intune has no status for that side of the object type.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Id of the app, policy or script
    $Id = $Request.Query.ID
    # Graph collection of the object: mobileApps, configurationPolicies, deviceCompliancePolicies, deviceManagementScripts, an app protection type, ...
    $Type = $Request.Query.Type

    # The id goes into OData filters and URLs, so only id characters are accepted (app protection ids look like T_<guid>)
    if ([string]::IsNullOrWhiteSpace($Type) -or "$Id" -notmatch '^[A-Za-z0-9_-]+$') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'A valid ID and Type are required.' }
            })
    }

    $MamTypes = @{
        androidManagedAppProtection           = 'androidManagedAppProtections'
        iosManagedAppProtection               = 'iosManagedAppProtections'
        windowsManagedAppProtection           = 'windowsManagedAppProtections'
        mdmWindowsInformationProtectionPolicy = 'mdmWindowsInformationProtectionPolicies'
        windowsInformationProtectionPolicy    = 'windowsInformationProtectionPolicies'
        targetedManagedAppConfiguration       = 'targetedManagedAppConfigurations'
    }

    $StatusTypes = @('mobileApps', 'deviceConfigurations', 'deviceCompliancePolicies', 'mobileAppConfigurations', 'configurationPolicies', 'groupPolicyConfigurations', 'intents', 'deviceManagementScripts', 'deviceShellScripts', 'deviceHealthScripts')
    # List pages send URLName in mixed casing (DeviceConfigurations); use the Graph segment's own casing
    $Type = @($StatusTypes + $MamTypes.Keys + $MamTypes.Values | Where-Object { $_ -eq $Type })[0] ?? $Type
    $IsMam = $MamTypes.ContainsKey($Type) -or $MamTypes.ContainsValue($Type)

    # nonCompliant -> Non compliant
    $Friendly = {
        param($Value)
        if ([string]::IsNullOrWhiteSpace("$Value")) { return 'Unknown' }
        $Text = ("$Value" -creplace '(?<!^)([A-Z])', ' $1').ToLower()
        $Text.Substring(0, 1).ToUpper() + $Text.Substring(1)
    }

    $DeviceRow = {
        param($DeviceName, $UserPrincipalName, $Status, $StatusDetail, $Platform, $LastReported)
        [PSCustomObject]@{
            DeviceName        = $DeviceName
            UserPrincipalName = $UserPrincipalName
            Status            = $Status
            StatusDetail      = $StatusDetail
            Platform          = $Platform
            # Intune reports 0001-01-01 for devices that never checked in
            LastReported      = if (($LastReported -as [datetime]).Year -eq 1) { $null } else { $LastReported }
        }
    }

    $UserRow = {
        param($UserPrincipalName, $UserName, $Status, $StatusDetail, $DeviceCount, $LastReported)
        [PSCustomObject]@{
            UserPrincipalName = $UserPrincipalName
            UserName          = $UserName
            Status            = $Status
            StatusDetail      = $StatusDetail
            DeviceCount       = $DeviceCount
            LastReported      = $LastReported
        }
    }

    # Types without a user report get one row per user from the device rows, carrying that user's worst status
    $StatusRank = @('Error', 'Failed', 'Fail', 'Script error', 'Conflict', 'Non compliant', 'Pending', 'In progress', 'Succeeded', 'Success', 'Compliant', 'Not applicable')
    $UsersFromDevices = {
        param($Devices)
        foreach ($Group in @($Devices | Group-Object -Property UserPrincipalName)) {
            $Worst = $Group.Group | Sort-Object { $Rank = $StatusRank.IndexOf("$($_.Status)"); if ($Rank -lt 0) { 99 } else { $Rank } } | Select-Object -First 1
            $Latest = ($Group.Group | Sort-Object LastReported -Descending | Select-Object -First 1).LastReported
            & $UserRow ($Group.Name ? $Group.Name : $null) ($Group.Name ? $null : 'No user') $Worst.Status $null $Group.Count $Latest
        }
    }

    $Devices = $null
    $Users = $null
    try {
        switch ($Type) {
            'mobileApps' {
                $Devices = foreach ($Row in (Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri 'https://graph.microsoft.com/beta/deviceManagement/reports/retrieveDeviceAppInstallationStatusReport' -Filter "(ApplicationId eq '$Id')" -OrderBy @())) {
                    $Detail = @($Row.AppInstallStateDetails_loc, $Row.HexErrorCode) | Where-Object { $_ }
                    & $DeviceRow $Row.DeviceName $Row.UserPrincipalName ($Row.AppInstallState_loc ?? (& $Friendly $Row.AppInstallState)) ($Detail -join ' ') $Row.Platform $Row.LastModifiedDateTime
                }
                $Users = foreach ($Row in (Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri 'https://graph.microsoft.com/beta/deviceManagement/reports/getUserInstallStatusReport' -Filter "(ApplicationId eq '$Id')" -OrderBy @())) {
                    $Status = if ($Row.FailedCount) { 'Failed' } elseif ($Row.PendingInstallCount) { 'Install pending' } elseif ($Row.NotInstalledCount) { 'Not installed' } elseif ($Row.InstalledCount) { 'Installed' } else { 'Not applicable' }
                    $DeviceCount = $Row.InstalledCount + $Row.FailedCount + $Row.PendingInstallCount + $Row.NotInstalledCount + $Row.NotApplicableCount
                    & $UserRow $Row.UserPrincipalName $Row.UserName $Status "$($Row.InstalledCount) installed, $($Row.FailedCount) failed, $($Row.PendingInstallCount) pending, $($Row.NotInstalledCount) not installed, $($Row.NotApplicableCount) not applicable" $DeviceCount $null
                }
            }
            { $_ -in @('deviceConfigurations', 'deviceCompliancePolicies', 'mobileAppConfigurations') } {
                $Base = if ($Type -eq 'mobileAppConfigurations') { 'deviceAppManagement' } else { 'deviceManagement' }
                # The Intune portal calls a compliant configuration profile Succeeded, compliance policies keep Compliant
                $StatusText = { param($Value) if ($Value -eq 'compliant' -and $Type -ne 'deviceCompliancePolicies') { 'Succeeded' } else { & $Friendly $Value } }
                $Devices = foreach ($Row in (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$Base/$Type('$Id')/deviceStatuses" -tenantid $TenantFilter)) {
                    & $DeviceRow $Row.deviceDisplayName $Row.userPrincipalName (& $StatusText $Row.status) $null $Row.deviceModel $Row.lastReportedDateTime
                }
                $Users = foreach ($Row in (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$Base/$Type('$Id')/userStatuses" -tenantid $TenantFilter)) {
                    # The row without a user is Intune's system account (device-targeted check-ins)
                    & $UserRow ($Row.userPrincipalName ? $Row.userPrincipalName : $null) ($Row.userDisplayName ? $Row.userDisplayName : 'System account') (& $StatusText $Row.status) $null $Row.devicesCount $Row.lastReportedDateTime
                }
            }
            { $_ -in @('configurationPolicies', 'groupPolicyConfigurations', 'intents') } {
                $PolicyTypes = @(
                    'Microsoft.Management.Services.Api.DeviceConfiguration'
                    'DeviceManagementConfigurationPolicy'
                    'DeviceConfigurationAdmxPolicy'
                    'Microsoft.Management.Services.Api.DeviceManagementIntent'
                )
                $TypeFilter = ($PolicyTypes | ForEach-Object { "(PolicyBaseTypeName eq '$_')" }) -join ' or '
                $Devices = foreach ($Row in (Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri 'https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport' -Filter "($TypeFilter) and (PolicyId eq '$Id')" -OrderBy @())) {
                    & $DeviceRow $Row.DeviceName $Row.UPN ($Row.ReportStatus_loc ?? $Row.ReportStatus) $null $Row.UnifiedPolicyPlatformType_loc $Row.PspdpuLastModifiedTimeUtc
                }
                $Users = @(& $UsersFromDevices $Devices)
            }
            { $_ -in @('deviceManagementScripts', 'deviceShellScripts', 'deviceHealthScripts') } {
                $Uri = "https://graph.microsoft.com/beta/deviceManagement/$Type('$Id')/deviceRunStates?`$expand=managedDevice(`$select=deviceName,userPrincipalName,operatingSystem)"
                $Devices = foreach ($Row in (New-GraphGetRequest -uri $Uri -tenantid $TenantFilter)) {
                    if ($Type -eq 'deviceHealthScripts') {
                        # Remediations report detection and remediation separately
                        $Status = & $Friendly $Row.detectionState
                        $Detail = "Remediation: $(& $Friendly $Row.remediationState)"
                    } else {
                        $Status = & $Friendly $Row.runState
                        $Detail = $Row.errorDescription
                    }
                    & $DeviceRow $Row.managedDevice.deviceName $Row.managedDevice.userPrincipalName $Status $Detail $Row.managedDevice.operatingSystem $Row.lastStateUpdateDateTime
                }
                if ($Type -eq 'deviceHealthScripts') {
                    $Users = @(& $UsersFromDevices $Devices)
                } else {
                    $Users = foreach ($Row in (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$Type('$Id')/userRunStates" -tenantid $TenantFilter)) {
                        $Status = if ($Row.errorDeviceCount) { 'Error' } else { 'Success' }
                        & $UserRow $Row.userPrincipalName $null $Status "$($Row.successDeviceCount) succeeded, $($Row.errorDeviceCount) failed" ($Row.successDeviceCount + $Row.errorDeviceCount) $null
                    }
                }
            }
            { $IsMam } {
                # App protection has no device install state; its user status is the app registrations the policy applies to
                $Registrations = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/managedAppRegistrations?`$expand=appliedPolicies(`$select=id)" -tenantid $TenantFilter) |
                    Where-Object { @($_.appliedPolicies.id) -contains $Id }
                $UserIds = @($Registrations.userId | Where-Object { $_ } | Sort-Object -Unique)
                $UserLookup = @{}
                if ($UserIds.Count -gt 0) {
                    $UserRequests = foreach ($UserId in $UserIds) {
                        @{ id = $UserId; method = 'GET'; url = "/users/$($UserId)?`$select=id,userPrincipalName,displayName" }
                    }
                    foreach ($Result in @(New-GraphBulkRequest -Requests @($UserRequests) -tenantid $TenantFilter)) {
                        if ($Result.body.id) { $UserLookup[$Result.id] = $Result.body }
                    }
                }
                $Users = foreach ($Row in $Registrations) {
                    $Flags = @($Row.flaggedReasons | Where-Object { $_ -and $_ -ne 'none' })
                    $Status = if ($Flags.Count -gt 0) { & $Friendly $Flags[0] } else { 'Checked in' }
                    $App = $Row.appIdentifier.bundleId ?? $Row.appIdentifier.packageId ?? $Row.appIdentifier.windowsAppId
                    $User = $UserLookup[$Row.userId]
                    & $UserRow ($User.userPrincipalName ?? $Row.userId) $User.displayName $Status "$App on $($Row.deviceName) ($($Row.deviceType))" $null $Row.lastSyncDateTime
                }
            }
            default {
                # Known Intune types without a per-object status source (update profiles, hardware configurations, ...)
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to load deployment status for $Type $($Id): $($ErrorMessage.NormalizedError)" }
            })
    }

    $Supported = $Type -in $StatusTypes
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results = [ordered]@{
                    # The leading comma stops the if-expression unrolling 0 or 1 rows into null or a lone object
                    Devices = if ($Supported) { , @($Devices) } else { $null }
                    Users   = if ($Supported -or $IsMam) { , @($Users) } else { $null }
                }
            }
        })
}

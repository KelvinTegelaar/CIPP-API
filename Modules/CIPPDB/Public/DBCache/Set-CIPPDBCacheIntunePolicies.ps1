function Set-CIPPDBCacheIntunePolicies {
    <#
    .SYNOPSIS
        Caches all Intune policies for a tenant (if Intune capable)

    .PARAMETER TenantFilter
        The tenant to cache Intune policies for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntunePoliciesCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune policies' -sev Debug

        # Family failures are accumulated so healthy families can still refresh.
        $Warnings = [System.Collections.Generic.List[string]]::new()
        $AddWarning = {
            param([string]$Message)
            $Warnings.Add($Message)
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $Message -sev Warning
        }

        # The report-backed families come from the same canonical definition as
        # Invoke-ListIntunePolicy and Get-CIPPIntunePolicyReport.
        $PolicyTypes = [System.Collections.Generic.List[object]]::new()
        foreach ($Definition in @(Get-CIPPIntunePolicyListDefinitions)) {
            $PolicyTypes.Add([PSCustomObject]@{
                    Type                  = $Definition.Id
                    CacheType             = $Definition.CacheType
                    Uri                   = $Definition.CacheUri
                    FetchDeviceStatuses   = [bool]$Definition.FetchDeviceStatuses
                    FetchAssignments      = [bool]$Definition.FetchAssignments
                    IncludeInPolicyReport = $true
                })
        }

        # Preserve the additional datasets historically collected by IntunePolicies.
        foreach ($LegacyType in @(
                [PSCustomObject]@{ Type = 'WindowsAutopilotDeploymentProfiles'; CacheType = 'IntuneWindowsAutopilotDeploymentProfiles'; Uri = '/deviceManagement/windowsAutopilotDeploymentProfiles?$top=999&$expand=assignments' }
                [PSCustomObject]@{ Type = 'DeviceEnrollmentConfigurations'; CacheType = 'IntuneDeviceEnrollmentConfigurations'; Uri = '/deviceManagement/deviceEnrollmentConfigurations?$top=999'; FetchAssignments = $true }
                [PSCustomObject]@{ Type = 'DeviceManagementScripts'; CacheType = 'IntuneDeviceManagementScripts'; Uri = '/deviceManagement/deviceManagementScripts?$top=999&$expand=assignments' }
                [PSCustomObject]@{ Type = 'MobileApps'; CacheType = 'IntuneMobileApps'; Uri = '/deviceAppManagement/mobileApps?$top=999&$select=id,displayName,description,publisher,isAssigned,createdDateTime,lastModifiedDateTime'; FetchAssignments = $true }
            )) {
            $PolicyTypes.Add($LegacyType)
        }

        $PolicyRequests = [System.Collections.Generic.List[object]]::new()
        $PolicyRequests.Add([PSCustomObject]@{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups?$top=999&$select=id,displayName'
            })
        foreach ($PolicyType in $PolicyTypes) {
            $PolicyRequests.Add([PSCustomObject]@{
                    id     = $PolicyType.Type
                    method = 'GET'
                    url    = $PolicyType.Uri
                })
        }

        try {
            $PolicyResults = @(New-GraphBulkRequest -Requests @($PolicyRequests) -tenantid $TenantFilter)
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch policies in bulk: $($_.Exception.Message)" -sev Error
            throw
        }

        # Cache the group snapshot used by this report without overwriting the richer,
        # tenant-wide Groups cache used elsewhere.
        $GroupResult = $PolicyResults | Where-Object { $_.id -eq 'Groups' } | Select-Object -First 1
        # Replace cached rows only after Graph confirms a successful 2xx response.
        if (-not $GroupResult) {
            & $AddWarning 'Intune policy group lookup returned no batch response; preserving the previous group snapshot'
        } elseif ($null -eq $GroupResult.status) {
            & $AddWarning 'Intune policy group lookup returned no HTTP status; preserving the previous group snapshot'
        } elseif ([int]$GroupResult.status -lt 200 -or [int]$GroupResult.status -ge 300) {
            $GroupError = $GroupResult.body.error.message ?? $GroupResult.body.message ?? 'Unknown Graph error'
            & $AddWarning "Intune policy group lookup failed with HTTP $($GroupResult.status): $GroupError; preserving the previous group snapshot"
        } else {
            $Groups = @($GroupResult.body.value)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntunePolicyGroups' -Data $Groups -AddCount -ClearOnEmpty
        }

        $SuccessfulPolicyTypes = 0
        $SuccessfulReportTypes = 0
        foreach ($PolicyType in $PolicyTypes) {
            $Result = $PolicyResults | Where-Object { $_.id -eq $PolicyType.Type } | Select-Object -First 1
            if (-not $Result) {
                & $AddWarning "No Graph batch response was returned for $($PolicyType.Type); preserving the previous cache"
                continue
            }

            # A missing status is not authoritative; retain the last good family cache.
            if ($null -eq $Result.status) {
                & $AddWarning "No HTTP status was returned for $($PolicyType.Type); preserving the previous cache"
                continue
            }

            if ([int]$Result.status -lt 200 -or [int]$Result.status -ge 300) {
                $GraphError = $Result.body.error.message ?? $Result.body.message ?? 'Unknown Graph error'
                & $AddWarning "Failed to cache $($PolicyType.Type): HTTP $($Result.status) - $GraphError; preserving the previous cache"
                continue
            }

            try {
                # Most Graph results wrap rows in value; retain direct-body support for legacy types.
                $Policies = if ($Result.body.PSObject.Properties.Name -contains 'value') {
                    @($Result.body.value)
                } elseif ($null -ne $Result.body) {
                    @($Result.body)
                } else {
                    @()
                }

                # Get assignments only for legacy collections whose list endpoints do
                # not support expand. Report-backed ManagedAppPolicies intentionally
                # remains identical to the live endpoint and does not use this fan-out.
                if ($PolicyType.FetchAssignments -and $Policies.Count -gt 0) {
                    $BaseUri = ($PolicyType.Uri -split '\?')[0]
                    $AssignmentRequests = @($Policies | ForEach-Object {
                            [PSCustomObject]@{
                                id     = $_.id
                                method = 'GET'
                                url    = "$BaseUri/$($_.id)/assignments"
                            }
                        })

                    try {
                        $AssignmentResults = @(New-GraphBulkRequest -Requests $AssignmentRequests -tenantid $TenantFilter)
                        foreach ($AssignResult in $AssignmentResults) {
                            if ($null -eq $AssignResult.status) {
                                & $AddWarning "No HTTP status was returned while fetching assignments for $($PolicyType.Type) policy $($AssignResult.id)"
                                continue
                            } elseif ([int]$AssignResult.status -lt 200 -or [int]$AssignResult.status -ge 300) {
                                & $AddWarning "Failed to fetch assignments for $($PolicyType.Type) policy $($AssignResult.id): HTTP $($AssignResult.status)"
                                continue
                            }

                            $Policy = $Policies | Where-Object { $_.id -eq $AssignResult.id } | Select-Object -First 1
                            if ($Policy) {
                                $Assignments = @($AssignResult.body.value)
                                $Policy | Add-Member -NotePropertyName assignments -NotePropertyValue $Assignments -Force
                            }
                        }
                    } catch {
                        & $AddWarning "Failed to fetch assignments for $($PolicyType.Type): $($_.Exception.Message)"
                    }
                }

                Add-CIPPDbItem -TenantFilter $TenantFilter -Type $PolicyType.CacheType -Data $Policies -AddCount -ClearOnEmpty
                $SuccessfulPolicyTypes++
                # Legacy-only success must not make an empty policy report look healthy.
                if ($PolicyType.IncludeInPolicyReport) { $SuccessfulReportTypes++ }
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Policies.Count) $($PolicyType.Type)" -sev Debug

                if ($PolicyType.FetchDeviceStatuses -and $Policies.Count -gt 0) {
                    $BaseUri = ($PolicyType.Uri -split '\?')[0]
                    $DeviceStatusRequests = @($Policies | ForEach-Object {
                            [PSCustomObject]@{
                                id     = $_.id
                                method = 'GET'
                                url    = "$BaseUri/$($_.id)/deviceStatuses?`$top=999"
                            }
                        })

                    try {
                        $DeviceStatusResults = @(New-GraphBulkRequest -Requests $DeviceStatusRequests -tenantid $TenantFilter)
                        foreach ($StatusResult in $DeviceStatusResults) {
                            if ($null -eq $StatusResult.status) {
                                & $AddWarning "No HTTP status was returned while fetching device statuses for $($PolicyType.Type) policy $($StatusResult.id)"
                                continue
                            } elseif ([int]$StatusResult.status -lt 200 -or [int]$StatusResult.status -ge 300) {
                                & $AddWarning "Failed to fetch device statuses for $($PolicyType.Type) policy $($StatusResult.id): HTTP $($StatusResult.status)"
                                continue
                            }

                            $Data = @($StatusResult.body.value)
                            if ($Data.Count -gt 0) {
                                $StatusType = "$($PolicyType.CacheType)_$($StatusResult.id)"
                                Add-CIPPDbItem -TenantFilter $TenantFilter -Type $StatusType -Data $Data
                                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Data.Count) device statuses for policy ID $($StatusResult.id)" -sev Debug
                            }
                        }
                    } catch {
                        & $AddWarning "Failed to fetch device statuses for $($PolicyType.Type): $($_.Exception.Message)"
                    }
                }
            } catch {
                & $AddWarning "Failed to process $($PolicyType.Type): $($_.Exception.Message); preserving any rows not replaced by this run"
            }
        }

        if ($SuccessfulPolicyTypes -eq 0 -or $SuccessfulReportTypes -eq 0) {
            throw 'No report-backed Intune policy families were cached successfully'
        }

        if ($Warnings.Count -gt 0) {
            $Summary = "Cached Intune policies with $($Warnings.Count) warning(s): $($Warnings -join '; ')"
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $Summary -sev Warning
            Write-Warning $Summary
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Intune policies successfully' -sev Debug
        }
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune policies: $($_.Exception.Message)" -sev Error
        throw
    }
}

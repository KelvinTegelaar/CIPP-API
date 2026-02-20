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
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntunePoliciesCache' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1') -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune policies' -sev Debug

        $PolicyTypes = @(
            @{ Type = 'DeviceCompliancePolicies'; Uri = '/deviceManagement/deviceCompliancePolicies?$top=999&$expand=assignments'; FetchDeviceStatuses = $true }
            @{ Type = 'DeviceConfigurations'; Uri = '/deviceManagement/deviceConfigurations?$top=999&$expand=assignments' }
            @{ Type = 'ConfigurationPolicies'; Uri = '/deviceManagement/configurationPolicies?$top=999&$expand=assignments,settings' }
            @{ Type = 'GroupPolicyConfigurations'; Uri = '/deviceManagement/groupPolicyConfigurations?$top=999&$expand=assignments' }
            @{ Type = 'MobileAppConfigurations'; Uri = '/deviceManagement/mobileAppConfigurations?$top=999&$expand=assignments' }
            @{ Type = 'AppProtectionPolicies'; Uri = '/deviceAppManagement/managedAppPolicies?$top=999'; FetchAssignments = $true }
            @{ Type = 'WindowsAutopilotDeploymentProfiles'; Uri = '/deviceManagement/windowsAutopilotDeploymentProfiles?$top=999&$expand=assignments' }
            @{ Type = 'DeviceEnrollmentConfigurations'; Uri = '/deviceManagement/deviceEnrollmentConfigurations?$top=999'; FetchAssignments = $true }
            @{ Type = 'DeviceManagementScripts'; Uri = '/deviceManagement/deviceManagementScripts?$top=999&$expand=assignments' }
            @{ Type = 'MobileApps'; Uri = '/deviceAppManagement/mobileApps?$top=999&$select=id,displayName,description,publisher,isAssigned,createdDateTime,lastModifiedDateTime'; FetchAssignments = $true }
        )

        # Build bulk requests for all policy types
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Fetching all policy types using bulk request' -sev Debug
        $PolicyRequests = foreach ($PolicyType in $PolicyTypes) {
            [PSCustomObject]@{
                id     = $PolicyType.Type
                method = 'GET'
                url    = $PolicyType.Uri
            }
        }

        try {
            $PolicyResults = New-GraphBulkRequest -Requests @($PolicyRequests) -tenantid $TenantFilter
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch policies in bulk: $($_.Exception.Message)" -sev Error
            throw
        }

        # Process each policy type result
        foreach ($Result in $PolicyResults) {
            $PolicyType = $PolicyTypes | Where-Object { $_.Type -eq $Result.id }
            if (-not $PolicyType) { continue }

            try {
                $Policies = $Result.body.value ?? $Result.body

                if (-not $Policies) {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No policies found for $($PolicyType.Type)" -sev Debug
                    continue
                }

                # Get assignments for policies that don't support expand using bulk requests
                if ($PolicyType.FetchAssignments -and ($Policies | Measure-Object).Count -gt 0) {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Fetching assignments for $($Policies.Count) $($PolicyType.Type) using bulk request" -sev Debug

                    $BaseUri = ($PolicyType.Uri -split '\?')[0]
                    # Build bulk request array for assignments
                    $AssignmentRequests = $Policies | ForEach-Object {
                        [PSCustomObject]@{
                            id     = $_.id
                            method = 'GET'
                            url    = "$BaseUri/$($_.id)/assignments"
                        }
                    }

                    try {
                        $AssignmentResults = New-GraphBulkRequest -Requests @($AssignmentRequests) -tenantid $TenantFilter

                        if ($AssignmentResults) {
                            foreach ($AssignResult in $AssignmentResults) {
                                $Policy = $Policies | Where-Object { $_.id -eq $AssignResult.id }
                                if ($Policy) {
                                    $Assignments = $AssignResult.body.value ?? $AssignResult.body
                                    $Policy | Add-Member -NotePropertyName 'assignments' -NotePropertyValue $Assignments -Force
                                }
                            }
                        }
                    } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch assignments in bulk for $($PolicyType.Type): $($_.Exception.Message)" -sev Warning
                    }
                }

                Add-CIPPDbItem -TenantFilter $TenantFilter -Type "Intune$($PolicyType.Type)" -Data $Policies
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type "Intune$($PolicyType.Type)" -Data $Policies -Count
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Policies.Count) $($PolicyType.Type)" -sev Debug

                # Fetch device statuses for compliance policies using bulk requests
                if ($PolicyType.FetchDeviceStatuses -and ($Policies | Measure-Object).Count -gt 0) {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Fetching device statuses for $($Policies.Count) compliance policies using bulk request" -sev Debug

                    $BaseUri = ($PolicyType.Uri -split '\?')[0]
                    # Build bulk request array
                    $DeviceStatusRequests = $Policies | ForEach-Object {
                        [PSCustomObject]@{
                            id     = $_.id
                            method = 'GET'
                            url    = "$BaseUri/$($_.id)/deviceStatuses?`$top=999"
                        }
                    }

                    try {
                        $DeviceStatusResults = New-GraphBulkRequest -Requests @($DeviceStatusRequests) -tenantid $TenantFilter

                        if ($DeviceStatusResults) {
                            foreach ($StatusResult in $DeviceStatusResults) {
                                $Data = $StatusResult.body.value ?? $StatusResult.body
                                if ($Data) {
                                    # Store device statuses with policy ID in the type name (matching extension cache pattern)
                                    $StatusType = "Intune$($PolicyType.Type)_$($StatusResult.id)"
                                    Add-CIPPDbItem -TenantFilter $TenantFilter -Type $StatusType -Data $Data
                                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Data | Measure-Object).Count) device statuses for policy ID $($StatusResult.id)" -sev Debug
                                }
                            }
                        }
                    } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch device statuses in bulk: $($_.Exception.Message)" -sev Warning
                    }
                }

                $Policies = $null

            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache $($PolicyType.Type): $($_.Exception.Message)" -sev Warning
            }
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Intune policies successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune policies: $($_.Exception.Message)" -sev Error
    }
}

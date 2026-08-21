function Set-CIPPDBCacheIntuneDeviceEnrollmentConfigurations {
    <#
    .SYNOPSIS
        Caches Intune device enrollment configurations under the legacy IntuneDeviceEnrollmentConfigurations type

    .DESCRIPTION
        Thin shim so the engine's on-miss lookup can refresh the 'IntuneDeviceEnrollmentConfigurations'
        cache type on its own. Mirrors exactly what Set-CIPPDBCacheIntunePolicies writes for this type
        today: the delegated deviceEnrollmentConfigurations list with per-configuration assignments
        attached as an 'assignments' property.

    .PARAMETER TenantFilter
        The tenant to cache device enrollment configurations for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneDeviceEnrollmentConfigurationsCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping Intune device enrollment configurations cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune device enrollment configurations' -sev Debug

        # Same fetch as Set-CIPPDBCacheIntunePolicies performs for this cache type: delegated auth,
        # $top=999, assignments fanned out per configuration because the list endpoint does not
        # support $expand=assignments.
        $Configurations = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?$top=999' -tenantid $TenantFilter)

        if ($Configurations.Count -gt 0) {
            $AssignmentRequests = @($Configurations | ForEach-Object {
                    [PSCustomObject]@{
                        id     = $_.id
                        method = 'GET'
                        url    = "/deviceManagement/deviceEnrollmentConfigurations/$($_.id)/assignments"
                    }
                })

            try {
                $AssignmentResults = @(New-GraphBulkRequest -Requests $AssignmentRequests -tenantid $TenantFilter)
                foreach ($AssignResult in $AssignmentResults) {
                    if ($null -eq $AssignResult.status) {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No HTTP status was returned while fetching assignments for enrollment configuration $($AssignResult.id)" -sev Warning
                        continue
                    } elseif ([int]$AssignResult.status -lt 200 -or [int]$AssignResult.status -ge 300) {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch assignments for enrollment configuration $($AssignResult.id): HTTP $($AssignResult.status)" -sev Warning
                        continue
                    }

                    $Configuration = $Configurations | Where-Object { $_.id -eq $AssignResult.id } | Select-Object -First 1
                    if ($Configuration) {
                        $Assignments = @($AssignResult.body.value)
                        $Configuration | Add-Member -NotePropertyName assignments -NotePropertyValue $Assignments -Force
                    }
                }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch assignments for device enrollment configurations: $($_.Exception.Message)" -sev Warning
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceEnrollmentConfigurations' -Data @($Configurations) -AddCount -ClearOnEmpty

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Configurations.Count) Intune device enrollment configurations" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune device enrollment configurations: $($_.Exception.Message)" -sev Error
    }
}

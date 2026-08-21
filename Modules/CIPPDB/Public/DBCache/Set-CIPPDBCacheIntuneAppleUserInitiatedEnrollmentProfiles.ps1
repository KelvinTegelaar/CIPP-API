function Set-CIPPDBCacheIntuneAppleUserInitiatedEnrollmentProfiles {
    <#
    .SYNOPSIS
        Caches Apple user-initiated enrollment type profiles (with assignments) for a tenant.

    .DESCRIPTION
        Thin single-family collector for the IntuneAppleUserInitiatedEnrollmentProfiles cache
        type, which the Set-CIPPDBCacheIntunePolicies umbrella also writes on its schedule. It
        exists so the convention lookup (Set-CIPPDBCache<Type>) resolves for collect-on-miss
        and for the post-remediation refresh. Assignments are fanned out per profile because
        the list endpoint does not support $expand=assignments.

    .PARAMETER TenantFilter
        The tenant to cache Apple enrollment type profiles for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneAppleEnrollmentProfilesCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping Apple enrollment type profiles cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Apple enrollment type profiles' -sev Debug
        $Profiles = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/appleUserInitiatedEnrollmentProfiles?$top=999' -tenantid $TenantFilter)

        if ($Profiles.Count -gt 0) {
            $AssignmentRequests = @($Profiles | ForEach-Object {
                    [PSCustomObject]@{
                        id     = $_.id
                        method = 'GET'
                        url    = "/deviceManagement/appleUserInitiatedEnrollmentProfiles/$($_.id)/assignments"
                    }
                })

            try {
                $AssignmentResults = @(New-GraphBulkRequest -Requests $AssignmentRequests -tenantid $TenantFilter)
                foreach ($AssignResult in $AssignmentResults) {
                    if ($null -eq $AssignResult.status) {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No HTTP status was returned while fetching assignments for Apple enrollment profile $($AssignResult.id)" -sev Warning
                        continue
                    } elseif ([int]$AssignResult.status -lt 200 -or [int]$AssignResult.status -ge 300) {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch assignments for Apple enrollment profile $($AssignResult.id): HTTP $($AssignResult.status)" -sev Warning
                        continue
                    }

                    $EnrollmentProfile = $Profiles | Where-Object { $_.id -eq $AssignResult.id } | Select-Object -First 1
                    if ($EnrollmentProfile) {
                        $Assignments = @($AssignResult.body.value)
                        $EnrollmentProfile | Add-Member -NotePropertyName assignments -NotePropertyValue $Assignments -Force
                    }
                }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to fetch assignments for Apple enrollment type profiles: $($_.Exception.Message)" -sev Warning
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppleUserInitiatedEnrollmentProfiles' -Data @($Profiles) -AddCount -ClearOnEmpty

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Profiles.Count) Apple enrollment type profiles" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Apple enrollment type profiles: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}

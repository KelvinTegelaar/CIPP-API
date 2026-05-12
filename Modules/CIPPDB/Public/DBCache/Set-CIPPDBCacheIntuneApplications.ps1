function Set-CIPPDBCacheIntuneApplications {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneApplicationsCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping applications cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune applications' -sev Debug
        $BulkRequests = @(
            @{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups?$top=999&$select=id,displayName'
            }
            @{
                id     = 'Apps'
                method = 'GET'
                url    = '/deviceAppManagement/mobileApps?$top=999&$expand=assignments&$filter=(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&$orderby=displayName'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
        $Apps = ($BulkResults | Where-Object { $_.id -eq 'Apps' }).body.value

        if (-not $Groups) { $Groups = @() }
        if (-not $Apps) { $Apps = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneApplicationGroups' -Data @($Groups)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneApplicationGroups' -Data @($Groups) -Count
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneApplications' -Data @($Apps)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneApplications' -Data @($Apps) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Apps | Measure-Object).Count) Intune applications" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune applications: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}

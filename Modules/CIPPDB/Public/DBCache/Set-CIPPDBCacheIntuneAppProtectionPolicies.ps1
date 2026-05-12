function Set-CIPPDBCacheIntuneAppProtectionPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneAppProtectionPoliciesCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping app protection policies cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune app protection and app configuration policies' -sev Debug

        $BulkRequests = @(
            @{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups?$top=999&$select=id,displayName'
            }
            @{
                id     = 'ManagedAppPolicies'
                method = 'GET'
                url    = '/deviceAppManagement/managedAppPolicies?$orderby=displayName'
            }
            @{
                id     = 'MobileAppConfigurations'
                method = 'GET'
                url    = '/deviceAppManagement/mobileAppConfigurations?$expand=assignments&$orderby=displayName'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
        $ManagedAppPolicies = ($BulkResults | Where-Object { $_.id -eq 'ManagedAppPolicies' }).body.value
        $MobileAppConfigs = ($BulkResults | Where-Object { $_.id -eq 'MobileAppConfigurations' }).body.value

        $ManagedAppPoliciesWithAssignments = [System.Collections.Generic.List[object]]::new()
        if ($ManagedAppPolicies) {
            $OdataTypes = ($ManagedAppPolicies | Select-Object -ExpandProperty '@odata.type' -Unique) -replace '#microsoft.graph.', ''
            $ManagedAppPoliciesBulkRequests = foreach ($type in $OdataTypes) {
                $urlSegment = switch ($type) {
                    'androidManagedAppProtection' { 'androidManagedAppProtections' }
                    'iosManagedAppProtection' { 'iosManagedAppProtections' }
                    'mdmWindowsInformationProtectionPolicy' { 'mdmWindowsInformationProtectionPolicies' }
                    'windowsManagedAppProtection' { 'windowsManagedAppProtections' }
                    'targetedManagedAppConfiguration' { 'targetedManagedAppConfigurations' }
                    default { $null }
                }
                if ($urlSegment) {
                    @{
                        id     = $type
                        method = 'GET'
                        url    = "/deviceAppManagement/${urlSegment}?`$expand=assignments&`$orderby=displayName"
                    }
                }
            }

            if ($ManagedAppPoliciesBulkRequests) {
                $ManagedAppPoliciesBulkResults = New-GraphBulkRequest -Requests @($ManagedAppPoliciesBulkRequests) -tenantid $TenantFilter
                foreach ($Result in $ManagedAppPoliciesBulkResults) {
                    foreach ($Policy in @($Result.body.value)) {
                        if ($null -eq $Policy) { continue }
                        $Policy | Add-Member -NotePropertyName 'URLName' -NotePropertyValue $Result.id -Force
                        $ManagedAppPoliciesWithAssignments.Add($Policy)
                    }
                }
            }
        }

        if (-not $Groups) { $Groups = @() }
        if (-not $MobileAppConfigs) { $MobileAppConfigs = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionPolicyGroups' -Data @($Groups)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionPolicyGroups' -Data @($Groups) -Count
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionManagedAppPolicies' -Data @($ManagedAppPoliciesWithAssignments)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionManagedAppPolicies' -Data @($ManagedAppPoliciesWithAssignments) -Count
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionMobileAppConfigurations' -Data @($MobileAppConfigs)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionMobileAppConfigurations' -Data @($MobileAppConfigs) -Count

        $TotalCount = (($ManagedAppPoliciesWithAssignments | Measure-Object).Count + ($MobileAppConfigs | Measure-Object).Count)
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $TotalCount app protection/configuration policies" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app protection policies: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}

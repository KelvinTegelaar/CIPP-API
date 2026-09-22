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
            # A license skip is still a completed collection: record authoritative empty sets for
            # every type this collector writes so collect-on-miss does not re-run it forever.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionPolicyGroups' -Data @() -AddCount -ClearOnEmpty
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionManagedAppPolicies' -Data @() -AddCount -ClearOnEmpty
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionMobileAppConfigurations' -Data @() -AddCount -ClearOnEmpty
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
        # A batch sub-request failure must PRESERVE the previous cache (rows and Count
        # metadata) - writing an empty collection on error poisons every consumer that
        # treats a fresh empty cache as authoritative (baseline drift detection).
        $GetChecked = {
            param($Results, $Id)
            $Result = $Results | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $Result -or $null -eq $Result.status -or [int]$Result.status -lt 200 -or [int]$Result.status -ge 300) {
                $GraphError = $Result.body.error.message ?? $Result.body.message ?? 'no batch response'
                throw "Graph request '$Id' failed (HTTP $($Result.status)): $GraphError - preserving the previous cache"
            }
            @($Result.body.value)
        }
        $Groups = & $GetChecked $BulkResults 'Groups'
        $ManagedAppPolicies = & $GetChecked $BulkResults 'ManagedAppPolicies'
        $MobileAppConfigs = & $GetChecked $BulkResults 'MobileAppConfigurations'

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
                    # Every per-type fetch must succeed - a partial set written as the
                    # full collection would report the failed types' policies as gone.
                    $Policies = & $GetChecked $ManagedAppPoliciesBulkResults $Result.id
                    foreach ($Policy in $Policies) {
                        if ($null -eq $Policy) { continue }
                        $Policy | Add-Member -NotePropertyName 'URLName' -NotePropertyValue $Result.id -Force
                        $ManagedAppPoliciesWithAssignments.Add($Policy)
                    }
                }
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionPolicyGroups' -Data @($Groups) -AddCount
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionManagedAppPolicies' -Data @($ManagedAppPoliciesWithAssignments) -AddCount
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionMobileAppConfigurations' -Data @($MobileAppConfigs) -AddCount

        $TotalCount = (($ManagedAppPoliciesWithAssignments | Measure-Object).Count + ($MobileAppConfigs | Measure-Object).Count)
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $TotalCount app protection/configuration policies" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app protection policies: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}

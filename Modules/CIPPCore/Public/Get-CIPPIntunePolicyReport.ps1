function Get-CIPPIntunePolicyReport {
    <#
    .SYNOPSIS
        Returns the Intune configuration policy list from the CIPP reporting database

    .DESCRIPTION
        Retrieves cached Intune policy data for a tenant, applies the same assignment name
        resolution and PolicyTypeName enrichment as the live Invoke-ListIntunePolicy endpoint,
        and returns a payload in the same shape.

        Note: The Windows update profile types (WindowsDriverUpdateProfiles,
        WindowsFeatureUpdateProfiles, windowsQualityUpdatePolicies, windowsQualityUpdateProfiles)
        are not currently cached; only the four types below are retrieved from cache:
            - DeviceConfigurations
            - ConfigurationPolicies
            - GroupPolicyConfigurations
            - MobileAppConfigurations

    .PARAMETER TenantFilter
        Tenant domain name or 'AllTenants'

    .EXAMPLE
        Get-CIPPIntunePolicyReport -TenantFilter 'contoso.onmicrosoft.com'

    .EXAMPLE
        Get-CIPPIntunePolicyReport -TenantFilter 'AllTenants'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # Maps DB cache type key -> Graph URL segment (URLName used by actions/deploy)
    $PolicyTypeMap = [ordered]@{
        IntuneDeviceConfigurations         = 'DeviceConfigurations'
        IntuneConfigurationPolicies        = 'ConfigurationPolicies'
        IntuneGroupPolicyConfigurations    = 'GroupPolicyConfigurations'
        IntuneMobileAppConfigurations      = 'MobileAppConfigurations'
        IntuneWindowsDriverUpdateProfiles  = 'WindowsDriverUpdateProfiles'
        IntuneWindowsFeatureUpdateProfiles = 'WindowsFeatureUpdateProfiles'
        IntuneWindowsQualityUpdatePolicies = 'WindowsQualityUpdatePolicies'
        IntuneWindowsQualityUpdateProfiles = 'WindowsQualityUpdateProfiles'
    }

    if ($TenantFilter -eq 'AllTenants') {
        # Collect all tenants that have any cached Intune policy data
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneDeviceConfigurations'
        $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

        $TenantList = Get-Tenants -IncludeErrors
        $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            try {
                $TenantResults = Get-CIPPIntunePolicyReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'IntunePolicyReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    try {
        # Load cached group display names for assignment resolution
        $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' |
            Where-Object { $_.RowKey -notlike '*-Count' }

        $Groups = foreach ($GroupItem in $GroupItems) {
            try { $GroupItem.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        }

        # Get cache timestamp from any available type
        $CacheTimestamp = $null

        $AllPolicies = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($TypeKey in $PolicyTypeMap.Keys) {
            $URLNameValue = $PolicyTypeMap[$TypeKey]

            $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $TypeKey |
                Where-Object { $_.RowKey -notlike '*-Count' }

            if (-not $Items) { continue }

            # Use the most recent Timestamp seen across all types
            $TypeTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
            if ($null -eq $CacheTimestamp -or ($TypeTimestamp -and $TypeTimestamp -gt $CacheTimestamp)) {
                $CacheTimestamp = $TypeTimestamp
            }

            foreach ($Item in $Items) {
                $Policy = try { $Item.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch { continue }

                if ($null -eq $Policy) { continue }

                # Determine PolicyTypeName using the same switch as the live endpoint
                $policyTypeName = switch -Wildcard ($Policy.'assignments@odata.context') {
                    '*microsoft.graph.windowsIdentityProtectionConfiguration*' { 'Identity Protection' }
                    '*microsoft.graph.windows10EndpointProtectionConfiguration*' { 'Endpoint Protection' }
                    '*microsoft.graph.windows10CustomConfiguration*' { 'Custom' }
                    '*microsoft.graph.windows10DeviceFirmwareConfigurationInterface*' { 'Firmware Configuration' }
                    '*groupPolicyConfigurations*' { 'Administrative Templates' }
                    '*windowsDomainJoinConfiguration*' { 'Domain Join configuration' }
                    '*windowsUpdateForBusinessConfiguration*' { 'Update Configuration' }
                    '*windowsHealthMonitoringConfiguration*' { 'Health Monitoring' }
                    '*microsoft.graph.macOSGeneralDeviceConfiguration*' { 'MacOS Configuration' }
                    '*microsoft.graph.macOSEndpointProtectionConfiguration*' { 'MacOS Endpoint Protection' }
                    '*microsoft.graph.androidWorkProfileGeneralDeviceConfiguration*' { 'Android Configuration' }
                    '*windowsFeatureUpdateProfiles*' { 'Feature Update' }
                    '*windowsQualityUpdatePolicies*' { 'Quality Update' }
                    '*windowsQualityUpdateProfiles*' { 'Quality Update' }
                    '*iosUpdateConfiguration*' { 'iOS Update Configuration' }
                    '*windowsDriverUpdateProfiles*' { 'Driver Update' }
                    '*configurationPolicies*' { 'Device Configuration' }
                    default { $Policy.'assignments@odata.context' }
                }

                # Resolve assignment names from cached group data
                $Assignments = $Policy.assignments.target | Select-Object -Property '@odata.type', groupId
                $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
                $PolicyExclude = [System.Collections.Generic.List[string]]::new()

                foreach ($target in $Assignments) {
                    switch ($target.'@odata.type') {
                        '#microsoft.graph.allDevicesAssignmentTarget' { $PolicyAssignment.Add('All Devices') }
                        '#microsoft.graph.exclusionallDevicesAssignmentTarget' { $PolicyExclude.Add('All Devices') }
                        '#microsoft.graph.allUsersAssignmentTarget' { $PolicyAssignment.Add('All Users') }
                        '#microsoft.graph.allLicensedUsersAssignmentTarget' { $PolicyAssignment.Add('All Licenced Users') }
                        '#microsoft.graph.exclusionallUsersAssignmentTarget' { $PolicyExclude.Add('All Users') }
                        '#microsoft.graph.groupAssignmentTarget' { $PolicyAssignment.Add(($Groups | Where-Object { $_.id -eq $target.groupId }).displayName) }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' { $PolicyExclude.Add(($Groups | Where-Object { $_.id -eq $target.groupId }).displayName) }
                        default {
                            $PolicyAssignment.Add($null)
                            $PolicyExclude.Add($null)
                        }
                    }
                }

                if ($null -eq $Policy.displayName) {
                    $Policy | Add-Member -NotePropertyName displayName -NotePropertyValue $Policy.name -Force
                }
                $Policy | Add-Member -NotePropertyName PolicyTypeName -NotePropertyValue $policyTypeName -Force
                $Policy | Add-Member -NotePropertyName URLName -NotePropertyValue $URLNameValue -Force
                $Policy | Add-Member -NotePropertyName PolicyAssignment -NotePropertyValue ($PolicyAssignment -join ', ') -Force
                $Policy | Add-Member -NotePropertyName PolicyExclude -NotePropertyValue ($PolicyExclude -join ', ') -Force
                $Policy | Add-Member -NotePropertyName CacheTimestamp -NotePropertyValue $CacheTimestamp -Force

                $AllPolicies.Add($Policy)
            }
        }

        # Apply the same filters as the live endpoint
        return ($AllPolicies | Where-Object { $_.platforms -ne 'linux' -and $_.templateReference.templateFamily -ne 'deviceConfigurationScripts' -and $null -ne $_.displayName } | Sort-Object -Property displayName)

    } catch {
        Write-LogMessage -API 'IntunePolicyReport' -tenant $TenantFilter -message "Failed to generate Intune policy report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}

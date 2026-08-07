function ConvertTo-CIPPIntunePolicyListItem {
    <#
    .SYNOPSIS
        Normalizes one Intune policy for the live or cached policy list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        # Empty Graph family responses can reach the shared normalizer as an explicit null.
        [AllowNull()]
        $Policy,

        [Parameter(Mandatory)]
        [string]$URLName,

        [AllowNull()]
        [string]$DefaultPolicyTypeName,

        [hashtable]$GroupLookup = @{}
    )

    process {
        if ($null -eq $Policy) { return }
        # Keep the shared live/cache filtering rules at the normalization boundary.
        if ($Policy.platforms -eq 'linux' -or $Policy.templateReference.templateFamily -eq 'deviceConfigurationScripts') { return }

        if ($null -eq $Policy.displayName) {
            $Policy | Add-Member -NotePropertyName displayName -NotePropertyValue $Policy.name -Force
        }
        if ($null -eq $Policy.displayName) { return }

        $AssignmentContext = $Policy.'assignments@odata.context'
        $PolicyODataType = $Policy.'@odata.type'
        # Prefer Graph's assignment context, then fall back to family-specific metadata.
        $PolicyTypeName = switch -Wildcard ($AssignmentContext) {
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
            '*deviceCompliancePolicies*' { 'Compliance Policy' }
            '*intents*' { 'Endpoint Security' }
            default { $null }
        }

        if ([string]::IsNullOrWhiteSpace($PolicyTypeName)) {
            if ($URLName -eq 'ManagedAppPolicies') {
                $PolicyTypeName = switch -Wildcard ($PolicyODataType) {
                    '*iosManagedAppProtection*' { 'iOS App Protection' }
                    '*androidManagedAppProtection*' { 'Android App Protection' }
                    '*windowsManagedAppProtection*' { 'Windows App Protection' }
                    default { $DefaultPolicyTypeName }
                }
            } elseif (-not [string]::IsNullOrWhiteSpace($DefaultPolicyTypeName)) {
                $PolicyTypeName = $DefaultPolicyTypeName
            } else {
                $PolicyTypeName = $AssignmentContext
            }
        }

        $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
        $PolicyExclude = [System.Collections.Generic.List[string]]::new()
        foreach ($Target in @($Policy.assignments.target)) {
            # Malformed or deleted group targets can omit groupId; unresolved names stay blank.
            switch ($Target.'@odata.type') {
                '#microsoft.graph.allDevicesAssignmentTarget' { $PolicyAssignment.Add('All Devices') }
                '#microsoft.graph.exclusionallDevicesAssignmentTarget' { $PolicyExclude.Add('All Devices') }
                '#microsoft.graph.allUsersAssignmentTarget' { $PolicyAssignment.Add('All Users') }
                '#microsoft.graph.allLicensedUsersAssignmentTarget' { $PolicyAssignment.Add('All Licenced Users') }
                '#microsoft.graph.exclusionallUsersAssignmentTarget' { $PolicyExclude.Add('All Users') }
                '#microsoft.graph.groupAssignmentTarget' {
                    $GroupId = [string]$Target.groupId
                    $PolicyAssignment.Add($(if ([string]::IsNullOrWhiteSpace($GroupId)) { $null } else { $GroupLookup[$GroupId] }))
                }
                '#microsoft.graph.exclusionGroupAssignmentTarget' {
                    $GroupId = [string]$Target.groupId
                    $PolicyExclude.Add($(if ([string]::IsNullOrWhiteSpace($GroupId)) { $null } else { $GroupLookup[$GroupId] }))
                }
                default {
                    $PolicyAssignment.Add($null)
                    $PolicyExclude.Add($null)
                }
            }
        }

        $Policy | Add-Member -NotePropertyName PolicyTypeName -NotePropertyValue $PolicyTypeName -Force
        $Policy | Add-Member -NotePropertyName URLName -NotePropertyValue $URLName -Force
        $Policy | Add-Member -NotePropertyName PolicyAssignment -NotePropertyValue ($PolicyAssignment -join ', ') -Force
        $Policy | Add-Member -NotePropertyName PolicyExclude -NotePropertyValue ($PolicyExclude -join ', ') -Force
        $Policy
    }
}

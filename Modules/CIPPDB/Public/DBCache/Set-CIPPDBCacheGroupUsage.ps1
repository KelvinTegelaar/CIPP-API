function Set-CIPPDBCacheGroupUsage {
    <#
    .SYNOPSIS
        Refreshes every reporting DB cache that feeds the group usage report

    .DESCRIPTION
        The group usage report is compiled at read time from existing cache types, so this
        collector writes no rows of its own — it runs the source collectors sequentially so
        a single on-demand sync refreshes all of them.

    .PARAMETER TenantFilter
        The tenant to refresh the source caches for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    $SourceTypes = @(
        'Groups'
        'ConditionalAccessPolicies'
        'IntunePolicies'
        'IntuneApplications'
        'IntuneAppProtectionPolicies'
        'IntuneScripts'
        'AutopilotDeploymentProfiles'
        'DeviceEnrollmentConfigurations'
        'Roles'
        'RoleAssignmentScheduleInstances'
        'RoleEligibilitySchedules'
        'AppRoleAssignments'
        'LicenseOverview'
        'ExoTransportRules'
    )

    foreach ($SourceType in $SourceTypes) {
        $FunctionName = "Set-CIPPDBCache$SourceType"
        try {
            $Params = @{ TenantFilter = $TenantFilter }
            if ($QueueId) { $Params.QueueId = $QueueId }
            & $FunctionName @Params
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Group usage sync: failed to refresh $SourceType : $($_.Exception.Message)" -sev Warning
        }
    }
}

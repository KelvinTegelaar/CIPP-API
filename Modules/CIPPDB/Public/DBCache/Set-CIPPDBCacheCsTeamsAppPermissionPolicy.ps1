function Set-CIPPDBCacheCsTeamsAppPermissionPolicy {
    <#
    .SYNOPSIS
        Caches the Teams App Permission Policy (all policies)

    .DESCRIPTION
        Calls Get-CsTeamsAppPermissionPolicy via New-TeamsRequest and writes
        the result into the CippReportingDB under Type
        'CsTeamsAppPermissionPolicy'. Used by CIS test 8.4.1.

    .PARAMETER TenantFilter
        The tenant to cache the app permission policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams App Permission Policies' -sev Debug

        $AppPermissionPolicies = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Get-CsTeamsAppPermissionPolicy'

        if ($AppPermissionPolicies) {
            $Data = @($AppPermissionPolicies)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsAppPermissionPolicy' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsAppPermissionPolicy' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Data.Count) Teams App Permission Policies" -sev Debug
        }
        $AppPermissionPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams App Permission Policies: $($_.Exception.Message)" -sev Error
    }
}

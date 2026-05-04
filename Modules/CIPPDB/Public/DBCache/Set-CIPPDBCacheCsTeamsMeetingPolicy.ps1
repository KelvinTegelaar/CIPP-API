function Set-CIPPDBCacheCsTeamsMeetingPolicy {
    <#
    .SYNOPSIS
        Caches the Teams Global Meeting Policy

    .DESCRIPTION
        Calls Get-CsTeamsMeetingPolicy via New-TeamsRequest and writes the
        result into the CippReportingDB under Type 'CsTeamsMeetingPolicy'.
        Used by CIS tests 8.5.1 - 8.5.9.

    .PARAMETER TenantFilter
        The tenant to cache the meeting policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams Meeting Policy' -sev Debug

        $MeetingPolicy = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{ Identity = 'Global' }

        if ($MeetingPolicy) {
            $Data = @($MeetingPolicy)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsMeetingPolicy' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsMeetingPolicy' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams Meeting Policy' -sev Debug
        }
        $MeetingPolicy = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Meeting Policy: $($_.Exception.Message)" -sev Error
    }
}

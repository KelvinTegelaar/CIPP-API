function Set-CIPPDBCacheCsTeamsFilesPolicy {
    <#
    .SYNOPSIS
        Caches the Teams Files Policy (Global)

    .DESCRIPTION
        Calls Get-CsTeamsFilesPolicy via New-TeamsRequestV2 and writes the
        result into the CippReportingDB under Type 'CsTeamsFilesPolicy'.
        Used by the TeamsFilesPolicy standard (external chat file sharing).

    .PARAMETER TenantFilter
        The tenant to cache the files policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams Files Policy' -sev Debug

        $FilesPolicy = New-TeamsRequestV2 -TenantFilter $TenantFilter -Type 'TeamsFilesPolicy' -Action Get -Identity 'Global'

        if ($FilesPolicy) {
            $Data = @($FilesPolicy)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsFilesPolicy' -Data $Data -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams Files Policy' -sev Debug
        } else {
            # The request succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsFilesPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Teams Files Policies (none found)' -sev Debug
        }
        $FilesPolicy = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Files Policy: $($_.Exception.Message)" -sev Error
    }
}

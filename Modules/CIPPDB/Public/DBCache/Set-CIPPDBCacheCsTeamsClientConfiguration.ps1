function Set-CIPPDBCacheCsTeamsClientConfiguration {
    <#
    .SYNOPSIS
        Caches the Teams Client Configuration (Global)

    .DESCRIPTION
        Calls Get-CsTeamsClientConfiguration via New-TeamsRequest and writes
        the result into the CippReportingDB under Type 'CsTeamsClientConfiguration'.
        Used by CIS tests 8.1.1 (external file sharing storage providers) and
        8.1.2 (channel email).

    .PARAMETER TenantFilter
        The tenant to cache the client configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams Client Configuration' -sev Debug

        $ClientConfig = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Get-CsTeamsClientConfiguration' -CmdParams @{ Identity = 'Global' }

        if ($ClientConfig) {
            $Data = @($ClientConfig)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsClientConfiguration' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTeamsClientConfiguration' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams Client Configuration' -sev Debug
        }
        $ClientConfig = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Client Configuration: $($_.Exception.Message)" -sev Error
    }
}

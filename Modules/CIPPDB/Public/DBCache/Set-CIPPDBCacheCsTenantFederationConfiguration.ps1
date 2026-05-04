function Set-CIPPDBCacheCsTenantFederationConfiguration {
    <#
    .SYNOPSIS
        Caches the Teams Tenant Federation Configuration

    .DESCRIPTION
        Calls Get-CsTenantFederationConfiguration via New-TeamsRequest and
        writes the result into the CippReportingDB under Type
        'CsTenantFederationConfiguration'. Used by CIS tests 8.2.1 (external
        domains allow/block list) and 8.2.4 (trial Teams tenants).

    .PARAMETER TenantFilter
        The tenant to cache the federation configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams Tenant Federation Configuration' -sev Debug

        $Federation = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Get-CsTenantFederationConfiguration' -CmdParams @{ Identity = 'Global' }

        if ($Federation) {
            $Data = @($Federation)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTenantFederationConfiguration' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsTenantFederationConfiguration' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams Tenant Federation Configuration' -sev Debug
        }
        $Federation = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams Tenant Federation Configuration: $($_.Exception.Message)" -sev Error
    }
}

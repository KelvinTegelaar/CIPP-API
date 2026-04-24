function Set-CIPPDBCacheMDEOnboarding {
    <#
    .SYNOPSIS
        Caches MDE onboarding status for a tenant
    .PARAMETER TenantFilter
        The tenant to cache MDE onboarding status for
    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [String]$TenantFilter,
        [String]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching MDE onboarding status' -sev Debug

        $ConnectorId = 'fc780465-2017-40d4-a0c5-307022471b92'
        $ConnectorUri = "https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/$ConnectorId"
        try {
            $ConnectorState = New-GraphGetRequest -uri $ConnectorUri -tenantid $TenantFilter
            $PartnerState = $ConnectorState.partnerState
        } catch {
            $PartnerState = 'unavailable'
        }

        $Result = @(
            [PSCustomObject]@{
                Tenant       = $TenantFilter
                partnerState = $PartnerState
                RowKey       = 'MDEOnboarding'
                PartitionKey = $TenantFilter
            }
        )

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MDEOnboarding' -Data @($Result)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MDEOnboarding' -Data @($Result) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached MDE onboarding status successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache MDE onboarding status: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}

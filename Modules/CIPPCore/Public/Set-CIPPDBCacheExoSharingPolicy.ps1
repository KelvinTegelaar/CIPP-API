function Set-CIPPDBCacheExoSharingPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Sharing Policies

    .PARAMETER TenantFilter
        The tenant to cache sharing policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Sharing Policies' -sev Debug

        $SharingPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SharingPolicy'

        if ($SharingPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSharingPolicy' -Data $SharingPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSharingPolicy' -Data $SharingPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SharingPolicies.Count) Sharing Policies" -sev Debug
        }
        $SharingPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Sharing Policies: $($_.Exception.Message)" -sev Error
    }
}

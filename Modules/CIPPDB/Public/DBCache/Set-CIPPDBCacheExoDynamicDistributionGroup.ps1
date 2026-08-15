function Set-CIPPDBCacheExoDynamicDistributionGroup {
    <#
    .SYNOPSIS
        Caches Exchange Online Dynamic Distribution Groups

    .PARAMETER TenantFilter
        The tenant to cache dynamic distribution groups for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Dynamic Distribution Groups' -sev Debug

        $DynamicGroups = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DynamicDistributionGroup' -Select 'Identity,Name,Alias,RecipientFilter,PrimarySmtpAddress,RequireSenderAuthenticationEnabled')

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDynamicDistributionGroup' -Data $DynamicGroups -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($DynamicGroups.Count) Dynamic Distribution Groups" -sev Debug
        $DynamicGroups = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Dynamic Distribution Groups: $($_.Exception.Message)" -sev Error
    }
}

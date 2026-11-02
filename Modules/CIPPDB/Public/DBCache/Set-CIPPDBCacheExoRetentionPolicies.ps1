function Set-CIPPDBCacheExoRetentionPolicies {
    <#
    .SYNOPSIS
        Caches Exchange Online Retention Policies

    .DESCRIPTION
        Caches Get-RetentionPolicy output including RetentionPolicyTagLinks, which the old
        RetentionPolicyTag standard checked to confirm a tag is linked to the
        'Default MRM Policy'.

    .PARAMETER TenantFilter
        The tenant to cache retention policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Retention Policies' -sev Debug

        $RetentionPolicies = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionPolicy')

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoRetentionPolicies' -Data $RetentionPolicies -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($RetentionPolicies.Count) Retention Policies" -sev Debug
        $RetentionPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Retention Policies: $($_.Exception.Message)" -sev Error
    }
}

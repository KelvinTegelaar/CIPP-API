function Set-CIPPDBCacheExoRetentionPolicyTags {
    <#
    .SYNOPSIS
        Caches Exchange Online Retention Policy Tags

    .DESCRIPTION
        Caches Get-RetentionPolicyTag output. Each tag carries the raw properties the old
        RetentionPolicyTag standard compared (Name, RetentionEnabled, RetentionAction,
        AgeLimitForRetention, Type) plus a derived AgeLimitForRetentionDays integer so
        baseline compares against a day count are numeric (AgeLimitForRetention itself is a
        timespan string like '30.00:00:00').

    .PARAMETER TenantFilter
        The tenant to cache retention policy tags for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Retention Policy Tags' -sev Debug

        $RetentionPolicyTags = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionPolicyTag')

        foreach ($Tag in $RetentionPolicyTags) {
            $AgeLimitDays = $null
            if ($Tag.AgeLimitForRetention) {
                try { $AgeLimitDays = [int]([timespan]$Tag.AgeLimitForRetention).TotalDays } catch { $AgeLimitDays = $null }
            }
            $Tag | Add-Member -NotePropertyName 'AgeLimitForRetentionDays' -NotePropertyValue $AgeLimitDays -Force
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoRetentionPolicyTags' -Data $RetentionPolicyTags -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($RetentionPolicyTags.Count) Retention Policy Tags" -sev Debug
        $RetentionPolicyTags = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Retention Policy Tags: $($_.Exception.Message)" -sev Error
    }
}

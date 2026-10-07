function Test-CIPPBaselineCacheCollected {
    <#
    .SYNOPSIS
        Tells a prepare hook whether a cache type has ever been collected for a tenant,
        independently of whether it holds any rows.
    .DESCRIPTION
        Zero rows means two completely different things and a hook cannot tell them apart by
        counting: the type has never been collected, or it was collected and the tenant
        genuinely has nothing. Add-CIPPDbItem writes a '<Type>-Count' metadata row either way,
        so its presence is the signal - DetectedApps-Count = 0 and ManagedDevices-Count = 0
        both exist on tenants that really have none.

        Use this ONLY where empty is a legitimate answer: a tenant with no Teams resource
        accounts or no registered devices is compliant, not unknown. Do NOT use it for a type
        whose emptiness implies a broken collection - an Exchange tenant with zero cached
        mailboxes is a collection failure, and reporting it compliant would be a lie.

        A lookup that fails is reported as NOT collected, so the caller falls back to No Data
        rather than claiming compliance it cannot prove.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    try {
        $Meta = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type -CountsOnly
        return ($null -ne ($Meta | Select-Object -First 1))
    } catch {
        Write-Information "Baselines: could not read collection metadata for $Type on $TenantFilter : $($_.Exception.Message)"
        return $false
    }
}

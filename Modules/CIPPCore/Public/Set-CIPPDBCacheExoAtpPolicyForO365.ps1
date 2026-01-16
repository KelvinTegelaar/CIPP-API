function Set-CIPPDBCacheExoAtpPolicyForO365 {
    <#
    .SYNOPSIS
        Caches Exchange Online ATP policies for Office 365

    .PARAMETER TenantFilter
        The tenant to cache ATP policy data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange ATP policies for Office 365' -sev Info

        $AtpPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AtpPolicyForO365'
        if ($AtpPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAtpPolicyForO365' -Data $AtpPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAtpPolicyForO365' -Data $AtpPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AtpPolicies.Count) ATP policies for Office 365" -sev Info
        }
        $AtpPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache ATP policy data: $($_.Exception.Message)" -sev Error
    }
}

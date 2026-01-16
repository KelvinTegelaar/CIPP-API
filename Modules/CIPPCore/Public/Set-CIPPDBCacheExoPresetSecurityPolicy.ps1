function Set-CIPPDBCacheExoPresetSecurityPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Preset Security Policies (EOP and ATP Protection Policy Rules)

    .PARAMETER TenantFilter
        The tenant to cache preset security policies for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Preset Security Policies' -sev Debug

        $EOPRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-EOPProtectionPolicyRule'
        $ATPRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ATPProtectionPolicyRule'

        # Combine both rule types into a single collection
        $AllRules = @()
        if ($EOPRules) {
            $AllRules += $EOPRules
        }
        if ($ATPRules) {
            $AllRules += $ATPRules
        }

        if ($AllRules.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoPresetSecurityPolicy' -Data $AllRules
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoPresetSecurityPolicy' -Data $AllRules -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllRules.Count) Preset Security Policy rules" -sev Debug
        }
        $EOPRules = $null
        $ATPRules = $null
        $AllRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Preset Security Policies: $($_.Exception.Message)" -sev Error
    }
}

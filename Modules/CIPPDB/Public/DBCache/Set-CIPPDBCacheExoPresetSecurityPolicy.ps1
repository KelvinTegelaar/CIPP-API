function Set-CIPPDBCacheExoPresetSecurityPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Preset Security Policies (EOP and ATP Protection Policy Rules)

    .PARAMETER TenantFilter
        The tenant to cache preset security policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Preset Security Policies' -sev Debug

        $MDOTestResult = Test-CIPPStandardLicense -StandardName 'ExoPresetSecurityPolicy' -TenantFilter $TenantFilter -Preset DefenderForOffice365 -SkipLog
        if ($MDOTestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Skipping Preset Security Policy cache: tenant lacks Microsoft Defender for Office 365' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoPresetSecurityPolicy' -Data @() -AddCount -ClearOnEmpty
            return
        }

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
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoPresetSecurityPolicy' -Data $AllRules -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllRules.Count) Preset Security Policy rules" -sev Debug
        } else {
            # Both cmdlets succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoPresetSecurityPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Preset Security Policy rules (none found)' -sev Debug
        }
        $EOPRules = $null
        $ATPRules = $null
        $AllRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Preset Security Policies: $($_.Exception.Message)" -sev Error
    }
}

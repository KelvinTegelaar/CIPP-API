function Set-CIPPDBCacheCopilotPolicySettings {
    <#
    .SYNOPSIS
        Caches Copilot admin policy settings for a tenant

    .DESCRIPTION
        Caches the five supported Copilot policy settings (Copilot Chat pinning, block access to open
        files, image generation, web search and admin center Copilot) as one row per setting with
        id, value and policyId.

    .PARAMETER TenantFilter
        The tenant to cache Copilot policy settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Copilot policy settings' -sev Debug

        $SettingIds = @(
            'microsoft.copilot.copilotchatpinning'
            'microsoft.copilot.blockaccesstoopenfiles'
            'microsoft.copilot.imagegeneration'
            'microsoft.copilot.allowwebsearch'
            'microsoft.copilot.allowinadmincenters'
        )

        # The Copilot policySettings API currently requires delegated auth (no -AsApp). The entity
        # carries a scalar 'value' property that is data rather than a collection envelope, so
        # -SkipValueExtraction returns the entity intact.
        $PolicySettings = foreach ($SettingId in $SettingIds) {
            try {
                $Current = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/copilot/admin/policySettings/$SettingId" -tenantid $TenantFilter -SkipValueExtraction
                [PSCustomObject]@{
                    id       = $SettingId
                    value    = $Current.value
                    policyId = $Current.policyId
                }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to get Copilot policy setting '$SettingId': $($_.Exception.Message)" -sev Warning
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotPolicySettings' -Data @($PolicySettings) -AddCount
        $PolicySettings = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Copilot policy settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot policy settings: $($_.Exception.Message)" -sev Error
    }
}

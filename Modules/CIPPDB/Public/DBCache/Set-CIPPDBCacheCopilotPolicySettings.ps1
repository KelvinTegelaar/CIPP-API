function Set-CIPPDBCacheCopilotPolicySettings {
    <#
    .SYNOPSIS
        Caches Copilot admin policy settings for a tenant

    .DESCRIPTION
        Caches the five supported Copilot policy settings (Copilot Chat pinning, block access to open
        files, image generation, web search and admin center Copilot) as ONE row whose properties are
        the CIPP setting keys, so a single declarative read can compare all five at once. The Graph
        policy ids each value came from are kept under policyIds
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

        # Keyed by the CIPP setting name the standard compares on, valued by the Graph
        # policySettings id the value is read from.
        $SettingMap = [ordered]@{
            copilotChatPinning     = 'microsoft.copilot.copilotchatpinning'
            blockAccessToOpenFiles = 'microsoft.copilot.blockaccesstoopenfiles'
            imageGeneration        = 'microsoft.copilot.imagegeneration'
            allowWebSearch         = 'microsoft.copilot.allowwebsearch'
            allowInAdminCenters    = 'microsoft.copilot.allowinadmincenters'
        }

        # The Copilot policySettings API currently requires delegated auth (no -AsApp). The entity
        # carries a scalar 'value' property that is data rather than a collection envelope, so
        # -SkipValueExtraction returns the entity intact.
        $Values = [ordered]@{}
        $PolicyIds = [ordered]@{}
        foreach ($Key in $SettingMap.Keys) {
            try {
                $Current = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/copilot/admin/policySettings/$($SettingMap[$Key])" -tenantid $TenantFilter -SkipValueExtraction
                # Graph returns these as opaque strings; keep them as strings so the compare
                # never turns "0" into a number and stops matching the configured value.
                $Values[$Key] = if ($null -eq $Current.value) { $null } else { [string]$Current.value }
                $PolicyIds[$Key] = $Current.policyId
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to get Copilot policy setting '$($SettingMap[$Key])': $($_.Exception.Message)" -sev Warning
                $Values[$Key] = $null
                $PolicyIds[$Key] = $null
            }
        }
        $Values['policyIds'] = [PSCustomObject]$PolicyIds

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotPolicySettings' -Data @([PSCustomObject]$Values) -AddCount
        $Values = $null
        $PolicyIds = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Copilot policy settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot policy settings: $($_.Exception.Message)" -sev Error
    }
}

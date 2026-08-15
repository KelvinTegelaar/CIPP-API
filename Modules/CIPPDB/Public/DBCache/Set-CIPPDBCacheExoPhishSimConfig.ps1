function Set-CIPPDBCacheExoPhishSimConfig {
    <#
    .SYNOPSIS
        Caches Exchange Online Phishing Simulation configuration

    .DESCRIPTION
        One collector, one bulk request, three typed writes serving the PhishingSimulations
        baseline:
        - Get-PhishSimOverridePolicy      -> ExoPhishSimOverridePolicy
        - Get-ExoPhishSimOverrideRule     -> ExoPhishSimOverrideRule
        - Get-TenantAllowBlockListItems (ListType Url, ListSubType AdvancedDelivery)
                                          -> ExoPhishSimUrlAllowItems

        Empty results are written as empty arrays: the absence of a phish sim override
        policy/rule is meaningful state, not a failed collection.

    .PARAMETER TenantFilter
        The tenant to cache phishing simulation configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Phishing Simulation configuration' -sev Debug

        $BulkRequests = @(
            @{ CmdletInput = @{ CmdletName = 'Get-PhishSimOverridePolicy'; Parameters = @{} } }
            @{ CmdletInput = @{ CmdletName = 'Get-ExoPhishSimOverrideRule'; Parameters = @{} } }
            @{ CmdletInput = @{ CmdletName = 'Get-TenantAllowBlockListItems'; Parameters = @{ ListType = 'Url'; ListSubType = 'AdvancedDelivery' } } }
        )
        $BulkResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $BulkRequests -useSystemMailbox $true -ReturnWithCommand $true

        $PhishSimPolicies = @($BulkResults.'Get-PhishSimOverridePolicy' | Where-Object { $_ })
        $PhishSimRules = @($BulkResults.'Get-ExoPhishSimOverrideRule' | Where-Object { $_ })
        $PhishSimUrlAllowItems = @($BulkResults.'Get-TenantAllowBlockListItems' | Where-Object { $_ })

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoPhishSimOverridePolicy' -Data $PhishSimPolicies -AddCount
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoPhishSimOverrideRule' -Data $PhishSimRules -AddCount
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoPhishSimUrlAllowItems' -Data $PhishSimUrlAllowItems -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached Phishing Simulation configuration: $($PhishSimPolicies.Count) policies, $($PhishSimRules.Count) rules, $($PhishSimUrlAllowItems.Count) URL allow items" -sev Debug

        $BulkResults = $null
        $PhishSimPolicies = $null
        $PhishSimRules = $null
        $PhishSimUrlAllowItems = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Phishing Simulation configuration: $($_.Exception.Message)" -sev Error
    }
}

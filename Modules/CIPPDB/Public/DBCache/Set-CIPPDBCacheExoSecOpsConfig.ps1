function Set-CIPPDBCacheExoSecOpsConfig {
    <#
    .SYNOPSIS
        Caches the Exchange Online SecOps mailbox (advanced delivery) configuration

    .DESCRIPTION
        One collector, one bulk request, two typed writes serving the SecOpsMailbox baseline:
        - Get-SecOpsOverridePolicy   -> ExoSecOpsOverridePolicy
        - Get-ExoSecOpsOverrideRule  -> ExoSecOpsOverrideRule

        Empty results are written as empty arrays: the absence of a SecOps override policy/rule
        is meaningful state, not a failed collection.

    .PARAMETER TenantFilter
        The tenant to cache SecOps mailbox configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SecOps mailbox configuration' -sev Debug

        $BulkRequests = @(
            @{ CmdletInput = @{ CmdletName = 'Get-SecOpsOverridePolicy'; Parameters = @{} } }
            @{ CmdletInput = @{ CmdletName = 'Get-ExoSecOpsOverrideRule'; Parameters = @{} } }
        )
        $BulkResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $BulkRequests -useSystemMailbox $true -ReturnWithCommand $true

        $SecOpsPolicies = @($BulkResults.'Get-SecOpsOverridePolicy' | Where-Object { $_ })
        $SecOpsRules = @($BulkResults.'Get-ExoSecOpsOverrideRule' | Where-Object { $_ })

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSecOpsOverridePolicy' -Data $SecOpsPolicies -AddCount -ClearOnEmpty
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSecOpsOverrideRule' -Data $SecOpsRules -AddCount -ClearOnEmpty

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached SecOps mailbox configuration: $($SecOpsPolicies.Count) policies, $($SecOpsRules.Count) rules" -sev Debug

        $BulkResults = $null
        $SecOpsPolicies = $null
        $SecOpsRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SecOps mailbox configuration: $($_.Exception.Message)" -sev Error
    }
}

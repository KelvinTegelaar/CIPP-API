function Set-CIPPDBCacheSensitivityLabels {
    <#
    .SYNOPSIS
        Caches sensitivity labels for a tenant (requires AIP/Purview license)

    .PARAMETER TenantFilter
        The tenant to cache sensitivity labels for

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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'SensitivityLabelsCache' -TenantFilter $TenantFilter -Preset Compliance -SkipLog

        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a Purview/AIP license, skipping sensitivity labels' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SensitivityLabels' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching sensitivity labels' -sev Debug

        $Labels = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/informationProtection/sensitivityLabels' -tenantid $TenantFilter -AsApp $true

        if ($Labels) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SensitivityLabels' -Data $Labels -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Labels.Count) sensitivity labels" -sev Debug
        } else {
            # The read succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SensitivityLabels' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 sensitivity labels (none found)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache sensitivity labels: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

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
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching sensitivity labels' -sev Debug

        $Labels = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/informationProtection/sensitivityLabels' -tenantid $TenantFilter -AsApp $true

        if ($Labels) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SensitivityLabels' -Data $Labels
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SensitivityLabels' -Data $Labels -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Labels.Count) sensitivity labels" -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache sensitivity labels: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

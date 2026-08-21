function Set-CIPPDBCacheExoLabels {
    <#
    .SYNOPSIS
        Caches Purview sensitivity labels from the Security & Compliance endpoint (requires Purview/AIP license)

    .DESCRIPTION
        Calls Get-Label against the Security & Compliance endpoint and writes the results into the
        CIPP database under Type 'ExoLabels'. Selects Name and DisplayName - the fields the
        SensitivityLabelTemplate standard matches deployed labels on. Distinct from the
        'SensitivityLabels' type, which caches the Graph informationProtection view.

    .PARAMETER TenantFilter
        The tenant to cache labels for

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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'ExoLabelsCache' -TenantFilter $TenantFilter -Preset Compliance -SkipLog

        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a Purview/AIP license, skipping compliance labels' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching compliance labels' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $Labels = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-Label' -Compliance -Select 'Name,DisplayName'

        if ($Labels) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoLabels' -Data @($Labels) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($Labels).Count) compliance labels" -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache compliance labels: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

function Set-CIPPDBCacheExoDlpSensitiveInfoTypes {
    <#
    .SYNOPSIS
        Caches Purview Sensitive Information Type rule packages for a tenant (requires Purview/AIP license)

    .DESCRIPTION
        Calls Get-DlpSensitiveInformationTypeRulePackage against the Security & Compliance endpoint and
        writes the raw rule packages (including the ClassificationRuleCollectionXml the SIT drift
        comparer parses via ConvertTo-CIPPSitComparable) into the CIPP database under Type
        'ExoDlpSensitiveInfoTypes'.

    .PARAMETER TenantFilter
        The tenant to cache SIT rule packages for

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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'ExoDlpSensitiveInfoTypesCache' -TenantFilter $TenantFilter -Preset Compliance -SkipLog

        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a Purview/AIP license, skipping sensitive information type rule packages' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching sensitive information type rule packages' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $RulePackages = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-DlpSensitiveInformationTypeRulePackage' -Compliance | Select-Object * -ExcludeProperty '*odata*', '*data.type*'

        if ($RulePackages) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDlpSensitiveInfoTypes' -Data @($RulePackages) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($RulePackages).Count) sensitive information type rule packages" -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache sensitive information type rule packages: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

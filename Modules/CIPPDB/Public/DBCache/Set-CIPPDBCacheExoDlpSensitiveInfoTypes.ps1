function Set-CIPPDBCacheExoDlpSensitiveInfoTypes {
    <#
    .SYNOPSIS
        Caches Purview Sensitive Information Type rule packages for a tenant (requires Purview/AIP license)

    .DESCRIPTION
        Calls Get-DlpSensitiveInformationTypeRulePackage against the Security & Compliance endpoint and
        writes the raw rule packages (including the ClassificationRuleCollectionXml the SIT drift
        comparer parses via ConvertTo-CIPPSitComparable) into the CIPP database under Type
        'ExoDlpSensitiveInfoTypes'. Only custom/tenant-authored rule packages are cached; the
        Microsoft built-in catalog is huge, identical across every tenant, and never read from this cache.

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
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDlpSensitiveInfoTypes' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching sensitive information type rule packages' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $RulePackages = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-DlpSensitiveInformationTypeRulePackage' -Compliance | Select-Object * -ExcludeProperty '*odata*', '*data.type*'
        # Drop Microsoft's built-in catalog packages, keeping only custom/tenant-authored ones. Fail-open:
        # a package with no Publisher is kept rather than risk losing a real custom pack.
        $RulePackages = @($RulePackages | Where-Object { $_.Publisher -notlike 'Microsoft*' })

        if ($RulePackages) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDlpSensitiveInfoTypes' -Data @($RulePackages) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($RulePackages).Count) sensitive information type rule packages" -sev Debug
        } else {
            # The read succeeded and no custom rule packages exist (the common case): write the
            # authoritative empty set so the Count marker records a completed collection and stale
            # rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDlpSensitiveInfoTypes' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 sensitive information type rule packages (no custom packages found)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache sensitive information type rule packages: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

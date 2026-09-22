function Set-CIPPDBCacheComplianceRetentionRules {
    <#
    .SYNOPSIS
        Caches Purview retention compliance rules for a tenant (requires Purview/AIP license)

    .DESCRIPTION
        Calls Get-RetentionComplianceRule against the Security & Compliance endpoint and writes the
        results into the CIPP database under Type 'ComplianceRetentionRules'. Uses the application
        token (-AsApp) because retention cmdlets are restricted for GDAP delegated identities.

    .PARAMETER TenantFilter
        The tenant to cache retention compliance rules for

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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'ComplianceRetentionRulesCache' -TenantFilter $TenantFilter -Preset Compliance -SkipLog

        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a Purview/AIP license, skipping retention compliance rules' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ComplianceRetentionRules' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching retention compliance rules' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $Rules = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-RetentionComplianceRule' -Compliance -AsApp | Select-Object * -ExcludeProperty '*odata*', '*data.type*'

        if ($Rules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ComplianceRetentionRules' -Data @($Rules) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($Rules).Count) retention compliance rules" -sev Debug
        } else {
            # The read succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ComplianceRetentionRules' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 retention compliance rules (none found)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache retention compliance rules: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

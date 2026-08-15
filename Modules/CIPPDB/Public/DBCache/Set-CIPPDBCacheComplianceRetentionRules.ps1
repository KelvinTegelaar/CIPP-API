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
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching retention compliance rules' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $Rules = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-RetentionComplianceRule' -Compliance -AsApp | Select-Object * -ExcludeProperty '*odata*', '*data.type*'

        if ($Rules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ComplianceRetentionRules' -Data @($Rules) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($Rules).Count) retention compliance rules" -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache retention compliance rules: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

function Set-CIPPDBCacheComplianceRetentionPolicies {
    <#
    .SYNOPSIS
        Caches Purview retention compliance policies for a tenant (requires Purview/AIP license)

    .DESCRIPTION
        Calls Get-RetentionCompliancePolicy against the Security & Compliance endpoint and writes the
        results into the CIPP database under Type 'ComplianceRetentionPolicies'. Uses the application
        token (-AsApp) because retention cmdlets are restricted for GDAP delegated identities.

    .PARAMETER TenantFilter
        The tenant to cache retention compliance policies for

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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'ComplianceRetentionPoliciesCache' -TenantFilter $TenantFilter -Preset Compliance -SkipLog

        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a Purview/AIP license, skipping retention compliance policies' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching retention compliance policies' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $Policies = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-RetentionCompliancePolicy' -Compliance -AsApp | Select-Object * -ExcludeProperty '*odata*', '*data.type*'

        if ($Policies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ComplianceRetentionPolicies' -Data @($Policies) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($Policies).Count) retention compliance policies" -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache retention compliance policies: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

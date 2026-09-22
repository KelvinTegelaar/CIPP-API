function Set-CIPPDBCacheDlpCompliancePolicies {
    <#
    .SYNOPSIS
        Caches DLP compliance policies and rules for a tenant (requires AIP/Purview license)

    .DESCRIPTION
        Caches the full Get-DlpCompliancePolicy objects under Type 'DlpCompliancePolicies' and the full
        Get-DlpComplianceRule objects under Type 'DlpComplianceRules', so template drift comparison
        (Compare-CIPPDlpCompliancePolicy, which allowlist-filters via Get-CIPPDlpComplianceFieldList and
        matches rules on ParentPolicyName) can run off cache.

    .PARAMETER TenantFilter
        The tenant to cache DLP policies for

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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'DlpCompliancePoliciesCache' -TenantFilter $TenantFilter -Preset Compliance -SkipLog

        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a Purview/AIP license, skipping DLP compliance policies' -sev Debug
            # A license skip is still a completed collection: record authoritative empty sets for
            # both types this collector writes so collect-on-miss does not re-run it forever.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DlpCompliancePolicies' -Data @() -AddCount -ClearOnEmpty
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DlpComplianceRules' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching DLP compliance policies' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        # Full objects (no -Select): the template compare needs every field in the
        # Get-CIPPDlpComplianceFieldList Policy allowlist (Comment, Mode, all *Location* fields, ...).
        $Policies = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-DlpCompliancePolicy' -Compliance | Select-Object * -ExcludeProperty '*odata*', '*data.type*'

        if ($Policies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DlpCompliancePolicies' -Data @($Policies) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($Policies).Count) DLP compliance policies" -sev Debug
        } else {
            # The read succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DlpCompliancePolicies' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 DLP compliance policies (none found)' -sev Debug
        }

        # Full rule objects: the compare needs the Rule allowlist fields (AdvancedRule, conditions,
        # actions, ...) plus ParentPolicyName to match rules to their parent policy.
        $Rules = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-DlpComplianceRule' -Compliance | Select-Object * -ExcludeProperty '*odata*', '*data.type*'

        if ($Rules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DlpComplianceRules' -Data @($Rules) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($Rules).Count) DLP compliance rules" -sev Debug
        } else {
            # The read succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DlpComplianceRules' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 DLP compliance rules (none found)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache DLP compliance policies/rules: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

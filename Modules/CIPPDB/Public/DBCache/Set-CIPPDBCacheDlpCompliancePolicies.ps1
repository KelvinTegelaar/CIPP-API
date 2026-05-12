function Set-CIPPDBCacheDlpCompliancePolicies {
    <#
    .SYNOPSIS
        Caches DLP compliance policies for a tenant (requires AIP/Purview license)

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
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching DLP compliance policies' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $Policies = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-DlpCompliancePolicy' -Compliance -Select 'Name,DisplayName,Mode,Enabled,Workload,CreatedBy,WhenCreatedUTC,WhenChangedUTC'

        if ($Policies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DlpCompliancePolicies' -Data $Policies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DlpCompliancePolicies' -Data $Policies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Policies.Count) DLP compliance policies" -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache DLP compliance policies: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}

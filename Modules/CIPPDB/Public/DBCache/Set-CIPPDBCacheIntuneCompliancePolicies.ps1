function Set-CIPPDBCacheIntuneCompliancePolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneCompliancePoliciesCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping compliance policies cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune compliance policies' -sev Debug
        $BulkRequests = @(
            @{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups?$top=999&$select=id,displayName'
            }
            @{
                id     = 'CompliancePolicies'
                method = 'GET'
                url    = '/deviceManagement/deviceCompliancePolicies?$expand=assignments&$orderby=displayName'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
        $Policies = ($BulkResults | Where-Object { $_.id -eq 'CompliancePolicies' }).body.value

        if (-not $Groups) { $Groups = @() }
        if (-not $Policies) { $Policies = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneCompliancePolicyGroups' -Data @($Groups)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneCompliancePolicyGroups' -Data @($Groups) -Count
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceCompliancePolicies' -Data @($Policies)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceCompliancePolicies' -Data @($Policies) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Policies | Measure-Object).Count) compliance policies" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache compliance policies: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}

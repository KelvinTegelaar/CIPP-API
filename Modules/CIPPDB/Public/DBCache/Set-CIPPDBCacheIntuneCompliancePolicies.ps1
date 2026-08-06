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
        # A batch sub-request failure must PRESERVE the previous cache (rows and Count
        # metadata) - writing an empty collection on error poisons every consumer that
        # treats a fresh empty cache as authoritative (baseline drift detection).
        $GetChecked = {
            param($Id)
            $Result = $BulkResults | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $Result -or $null -eq $Result.status -or [int]$Result.status -lt 200 -or [int]$Result.status -ge 300) {
                $GraphError = $Result.body.error.message ?? $Result.body.message ?? 'no batch response'
                throw "Graph request '$Id' failed (HTTP $($Result.status)): $GraphError - preserving the previous cache"
            }
            @($Result.body.value)
        }
        $Groups = & $GetChecked 'Groups'
        $Policies = & $GetChecked 'CompliancePolicies'

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneCompliancePolicyGroups' -Data @($Groups) -AddCount
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceCompliancePolicies' -Data @($Policies) -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Policies | Measure-Object).Count) compliance policies" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache compliance policies: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}

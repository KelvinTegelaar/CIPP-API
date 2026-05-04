function Invoke-CippTestCIS_1_3_7 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.3.7) - 'Third-party storage services' SHALL be restricted in 'Microsoft 365 on the web'
    #>
    param($Tenant)

    try {
        $ServicePrincipals = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipals'

        if (-not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_7' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ServicePrincipals cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "'Third-party storage services' are restricted in 'Microsoft 365 on the web'" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        # appId of "Microsoft 365 on the web" service principal
        $AppId = 'c1f33bc0-bdb4-4248-ba9b-096807ddb43e'
        $SP = $ServicePrincipals | Where-Object { $_.appId -eq $AppId } | Select-Object -First 1

        if (-not $SP) {
            $Status = 'Passed'
            $Result = 'The Microsoft 365 on the web service principal is not present in the tenant — third-party storage cannot be enabled.'
        } elseif ($SP.accountEnabled -eq $false) {
            $Status = 'Passed'
            $Result = "The Microsoft 365 on the web service principal exists but is disabled (accountEnabled: $($SP.accountEnabled))."
        } else {
            $Status = 'Failed'
            $Result = 'The Microsoft 365 on the web service principal is enabled. Disable it to restrict third-party storage providers.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_7' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "'Third-party storage services' are restricted in 'Microsoft 365 on the web'" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_7' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "'Third-party storage services' are restricted in 'Microsoft 365 on the web'" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}

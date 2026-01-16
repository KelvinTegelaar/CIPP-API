function Invoke-CippTestZTNA21780 {
    <#
    .SYNOPSIS
    No usage of ADAL in the tenant
    #>
    param($Tenant)
    #tested
    try {
        $Recommendations = New-CIPPDbRequest -TenantFilter $Tenant -Type 'DirectoryRecommendations'

        if (-not $Recommendations) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21780' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'No usage of ADAL in the tenant' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'
            return
        }

        $AdalRecommendations = $Recommendations | Where-Object {
            $_.recommendationType -eq 'adalToMsalMigration'
        }

        if ($AdalRecommendations.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No ADAL applications found in the tenant'
        } else {
            $Status = 'Failed'
            $Result = @"
            Found $($AdalRecommendations.Count) ADAL applications in the tenant that need migration to MSAL.
            ADAL Applications:
            $(($AdalRecommendations | ForEach-Object { "- $($_.applicationDisplayName) (AppId: $($_.applicationId))" }) -join "`n")
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21780' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'No usage of ADAL in the tenant' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21780' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'No usage of ADAL in the tenant' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'
    }
}

function Invoke-CippTestZTNA21809 {
    param($Tenant)
    #Tested
    try {
        $result = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AdminConsentRequestPolicy'

        if (-not $result) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21809' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Admin consent request policy not found in database' -Risk 'High' -Name 'Admin consent workflow is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
            return
        }

        $passed = if ($result.isEnabled) { 'Passed' } else { 'Failed' }

        if ($result.isEnabled) {
            $testResultMarkdown = 'Admin consent workflow is enabled.'
        } else {
            $testResultMarkdown = "Admin consent workflow is disabled.`n`nThe adminConsentRequestPolicy.isEnabled property is set to false."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21809' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'High' -Name 'Admin consent workflow is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21809' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Admin consent workflow is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
    }
}

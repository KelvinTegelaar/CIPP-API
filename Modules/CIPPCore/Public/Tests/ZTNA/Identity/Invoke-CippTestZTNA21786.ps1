function Invoke-CippTestZTNA21786 {
    <#
    .SYNOPSIS
    User sign-in activity uses token protection
    #>
    param($Tenant)
    #tested
    try {
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21786' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'User sign-in activity uses token protection' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        $TokenProtectionPolicies = $CAPolicies | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.clientAppTypes.Count -eq 1 -and
            $_.conditions.clientAppTypes[0] -eq 'mobileAppsAndDesktopClients' -and
            $_.conditions.applications.includeApplications -contains '00000002-0000-0ff1-ce00-000000000000' -and
            $_.conditions.applications.includeApplications -contains '00000003-0000-0ff1-ce00-000000000000' -and
            $_.conditions.platforms.includePlatforms.Count -eq 1 -and
            $_.conditions.platforms.includePlatforms -eq 'windows' -and
            $_.sessionControls.secureSignInSession.isEnabled -eq $true
        }

        if ($TokenProtectionPolicies.Count -gt 0) {
            $Status = 'Passed'
            $Result = "Found $($TokenProtectionPolicies.Count) token protection policies properly configured"
        } else {
            $Status = 'Failed'
            $Result = 'No properly configured token protection policies found'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21786' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'User sign-in activity uses token protection' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21786' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'User sign-in activity uses token protection' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
    }
}

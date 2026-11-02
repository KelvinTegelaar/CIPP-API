function Invoke-CippTestZTNA21775 {
    <#
    .SYNOPSIS
    Tenant app management policy is configured
    #>
    param($Tenant)

    try {
        $PolicyData = Get-CIPPTestData -TenantFilter $Tenant -Type 'DefaultAppManagementPolicy'

        if (-not $PolicyData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21775' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Tenant app management policy is configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }

        $Policy = if ($PolicyData -is [System.Collections.IList]) { $PolicyData[0] } else { $PolicyData }

        $Enabled = $Policy.isEnabled -eq $true
        $AppRestrictions = $Policy.applicationRestrictions
        $SpRestrictions = $Policy.servicePrincipalRestrictions

        $HasActiveRule = {
            param($Restrictions)
            if (-not $Restrictions) { return $false }
            foreach ($Section in 'passwordCredentials', 'keyCredentials') {
                $Rules = $Restrictions.$Section
                if ($Rules -and ($Rules.Where({ $_.state -eq 'enabled' })).Count -gt 0) {
                    return $true
                }
            }
            return $false
        }

        $AppHasRule = & $HasActiveRule $AppRestrictions
        $SpHasRule = & $HasActiveRule $SpRestrictions
        $Passed = $Enabled -and ($AppHasRule -or $SpHasRule)

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($Passed) {
            $Status = 'Passed'
            $Lines.Add('Tenant default app management policy is enabled with active credential restrictions.')
        } else {
            $Status = 'Failed'
            $Lines.Add('Tenant default app management policy is not properly configured.')
            $Lines.Add('')
            $Lines.Add("- **isEnabled:** $Enabled")
            $Lines.Add("- **applicationRestrictions has active rule:** $AppHasRule")
            $Lines.Add("- **servicePrincipalRestrictions has active rule:** $SpHasRule")
            $Lines.Add('')
            $Lines.Add('**Remediation:** Enable the default app management policy and configure credential restrictions to control how applications can use password and key credentials.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21775' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'Medium' -Name 'Tenant app management policy is configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21775' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Tenant app management policy is configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}

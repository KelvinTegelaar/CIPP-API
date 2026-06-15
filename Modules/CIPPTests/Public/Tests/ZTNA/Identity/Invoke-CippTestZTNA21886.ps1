function Invoke-CippTestZTNA21886 {
    <#
    .SYNOPSIS
    Applications are configured for automatic user provisioning
    #>
    param($Tenant)
    #Tested
    try {
        $ServicePrincipals = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipals'
        if (-not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21886' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Applications are configured for automatic user provisioning' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Applications management'
            return
        }

        $AppsWithSSO = $ServicePrincipals | Where-Object {
            $null -ne $_.preferredSingleSignOnMode -and
            $_.preferredSingleSignOnMode -in @('password', 'saml', 'oidc') -and
            $_.accountEnabled -eq $true
        }

        if (-not $AppsWithSSO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21886' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No applications configured for SSO found' -Risk 'Medium' -Name 'Applications are configured for automatic user provisioning' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Applications management'
            return
        }

        $Status = 'Investigate'

        $ResultLines = [System.Collections.Generic.List[string]]::new()
        $ResultLines.Add("Found $($AppsWithSSO.Count) application(s) configured for SSO.")
        $ResultLines.Add('')
        $ResultLines.Add('**Applications with SSO enabled:**')

        $SSOByType = $AppsWithSSO | Group-Object -Property preferredSingleSignOnMode
        foreach ($Group in $SSOByType) {
            $ResultLines.Add('')
            $ResultLines.Add("**$($Group.Name.ToUpper()) SSO** ($($Group.Count) app(s)):")
            $Top5 = $Group.Group | Select-Object -First 5
            foreach ($App in $Top5) {
                $ResultLines.Add("- $($App.displayName)")
            }
            if ($Group.Count -gt 5) {
                $ResultLines.Add("- ... and $($Group.Count - 5) more")
            }
        }

        $ResultLines.Add('')
        $ResultLines.Add('**Note:** Provisioning template and job validation requires Graph API synchronization endpoint not available in cache.')
        $ResultLines.Add('')
        $ResultLines.Add('**Recommendation:** Configure automatic user provisioning for applications that support it to ensure consistent access management.')

        $Result = $ResultLines -join "`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21886' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Applications are configured for automatic user provisioning' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Applications management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21886' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Applications are configured for automatic user provisioning' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Applications management'
    }
}

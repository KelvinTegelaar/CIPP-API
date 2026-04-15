function Invoke-CippTestZTNA21784 {
    <#
    .SYNOPSIS
    All user sign in activity uses phishing-resistant authentication methods
    #>
    param($Tenant)
    #tested
    try {
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21784' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'All user sign in activity uses phishing-resistant authentication methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        # Get authentication strength policies from cache
        $AuthStrengthPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationStrengths'

        # Define phishing-resistant methods
        $PhishingResistantMethods = @(
            'windowsHelloForBusiness',
            'fido2',
            'x509CertificateMultiFactor',
            'certificateBasedAuthenticationPki'
        )

        # Find authentication strength policies with phishing-resistant methods
        $PhishingResistantPolicies = $AuthStrengthPolicies | Where-Object {
            $_.allowedCombinations | Where-Object { $PhishingResistantMethods -contains $_ }
        }

        if (-not $PhishingResistantPolicies) {
            $Status = 'Failed'
            $Result = 'No phishing-resistant authentication strength policies found in tenant'
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21784' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'All user sign in activity uses phishing-resistant authentication methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        $EnabledPolicies = $CAPolicies | Where-Object { $_.state -eq 'enabled' }

        # Find policies that apply to all users with phishing-resistant auth strength
        $RelevantPolicies = $EnabledPolicies | Where-Object {
            ($_.conditions.users.includeUsers -contains 'All') -and
            ($_.grantControls.authenticationStrength.id -in $PhishingResistantPolicies.id)
        }

        if (-not $RelevantPolicies) {
            $Status = 'Failed'
            $Result = 'No Conditional Access policies found requiring phishing-resistant authentication for all users'
        } else {
            # Check for user exclusions that create coverage gaps
            $PoliciesWithExclusions = $RelevantPolicies | Where-Object {
                $_.conditions.users.excludeUsers.Count -gt 0
            }

            if ($PoliciesWithExclusions.Count -gt 0) {
                $Status = 'Failed'
                $Result = "Found $($RelevantPolicies.Count) policies requiring phishing-resistant authentication, but $($PoliciesWithExclusions.Count) have user exclusions creating coverage gaps:`n`n"
                $Result += ($PoliciesWithExclusions | ForEach-Object { "- $($_.displayName) (Excludes $($_.conditions.users.excludeUsers.Count) users)" }) -join "`n"
            } else {
                $Status = 'Passed'
                $Result = "All users are protected by $($RelevantPolicies.Count) Conditional Access policies requiring phishing-resistant authentication:`n`n"
                $Result += ($RelevantPolicies | ForEach-Object { "- $($_.displayName)" }) -join "`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21784' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'All user sign in activity uses phishing-resistant authentication methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21784' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'All user sign in activity uses phishing-resistant authentication methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    }
}

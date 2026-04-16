function Invoke-CippTestORCA239 {
    <#
    .SYNOPSIS
    No exclusions for built-in protection
    #>
    param($Tenant)

    try {
        $AntiPhishPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'
        $ContentFilterPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $AntiPhishPolicies -and -not $ContentFilterPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA239' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No policies found in database.' -Risk 'High' -Name 'No exclusions for built-in protection' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Configuration'
            return
        }

        $FailedPolicies = @()
        $Issues = @()

        # Check Anti-Phish policies for exclusions
        if ($AntiPhishPolicies) {
            foreach ($Policy in $AntiPhishPolicies) {
                $HasExclusions = $false
                $ExclusionDetails = @()

                if ($Policy.ExcludedSenders -and $Policy.ExcludedSenders.Count -gt 0) {
                    $HasExclusions = $true
                    $ExclusionDetails += "ExcludedSenders: $($Policy.ExcludedSenders.Count)"
                }

                if ($Policy.ExcludedDomains -and $Policy.ExcludedDomains.Count -gt 0) {
                    $HasExclusions = $true
                    $ExclusionDetails += "ExcludedDomains: $($Policy.ExcludedDomains.Count)"
                }

                if ($HasExclusions) {
                    $Issues += "Anti-Phish Policy '$($Policy.Identity)': $($ExclusionDetails -join ', ')"
                }
            }
        }

        # Check Content Filter policies for exclusions
        if ($ContentFilterPolicies) {
            foreach ($Policy in $ContentFilterPolicies) {
                $HasExclusions = $false
                $ExclusionDetails = @()

                if ($Policy.AllowedSenders -and $Policy.AllowedSenders.Count -gt 0) {
                    $HasExclusions = $true
                    $ExclusionDetails += "AllowedSenders: $($Policy.AllowedSenders.Count)"
                }

                if ($Policy.AllowedSenderDomains -and $Policy.AllowedSenderDomains.Count -gt 0) {
                    $HasExclusions = $true
                    $ExclusionDetails += "AllowedSenderDomains: $($Policy.AllowedSenderDomains.Count)"
                }

                if ($HasExclusions) {
                    $Issues += "Anti-Spam Policy '$($Policy.Identity)': $($ExclusionDetails -join ', ')"
                }
            }
        }

        if ($Issues.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No exclusions found in built-in protection policies."
        } else {
            $Status = 'Failed'
            $Result = "Found $($Issues.Count) policies with exclusions that bypass built-in protection.`n`n"
            $Result += "**Issues Found:**`n`n"
            foreach ($Issue in $Issues) {
                $Result += "- $Issue`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA239' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'No exclusions for built-in protection' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA239' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'No exclusions for built-in protection' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Configuration'
    }
}

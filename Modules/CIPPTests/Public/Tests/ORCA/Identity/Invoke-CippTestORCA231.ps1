function Invoke-CippTestORCA231 {
    <#
    .SYNOPSIS
    Each domain has an anti-spam policy
    #>
    param($Tenant)

    try {
        $AcceptedDomains = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAcceptedDomains'
        $ContentFilterRules = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterRule'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA231' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'Medium' -Name 'Each domain has an anti-spam policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Spam'
            return
        }

        $OverlappingDomains = [System.Collections.Generic.List[object]]::new()
        foreach ($Domain in $AcceptedDomains) {
            $ApplicableRules = @($ContentFilterRules | Where-Object {
                    $_.State -eq 'Enabled' -and
                    $_.RecipientDomainIs -contains $Domain.DomainName -and
                    $_.ExceptIfRecipientDomainIs -notcontains $Domain.DomainName
                })
            if ($ApplicableRules.Count -gt 1) {
                $OverlappingDomains.Add([PSCustomObject]@{
                        Domain = $Domain.DomainName
                        Rules  = $ApplicableRules
                    }) | Out-Null
            }
        }

        if ($OverlappingDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No overlapping Anti-spam policy rules were found.'
        } else {
            $Status = 'Informational'
            $Result = [System.Text.StringBuilder]::new("Multiple Anti-spam policy rules apply to one or more domains.`n`n")
            foreach ($Overlap in $OverlappingDomains) {
                $null = $Result.Append("- **$($Overlap.Domain)**`n")
                foreach ($Rule in ($Overlap.Rules | Sort-Object Priority)) {
                    $null = $Result.Append("  - $($Rule.Name)")
                    if ($null -ne $Rule.Priority) {
                        $null = $Result.Append(" (Priority: $($Rule.Priority))")
                    }
                    $null = $Result.Append("`n")
                }
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA231' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Each domain has an anti-spam policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA231' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Each domain has an anti-spam policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Spam'
    }
}

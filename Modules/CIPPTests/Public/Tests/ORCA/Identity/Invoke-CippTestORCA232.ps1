function Invoke-CippTestORCA232 {
    <#
    .SYNOPSIS
    Each domain has a malware filter policy
    #>
    param($Tenant)

    try {
        $AcceptedDomains = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAcceptedDomains'
        $MalwareRules = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterRules'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA232' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'Medium' -Name 'Each domain has a malware filter policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Malware'
            return
        }

        $OverlappingDomains = [System.Collections.Generic.List[object]]::new()
        foreach ($Domain in $AcceptedDomains) {
            $ApplicableRules = @($MalwareRules | Where-Object {
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
            $Result = 'No overlapping Malware filter policy rules were found.'
        } else {
            $Status = 'Informational'
            $Result = [System.Text.StringBuilder]::new("Multiple Malware filter policy rules apply to one or more domains.`n`n")
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

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA232' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Each domain has a malware filter policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Malware'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA232' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Each domain has a malware filter policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Malware'
    }
}

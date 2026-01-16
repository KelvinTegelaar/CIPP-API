function Invoke-CippTestORCA108_1 {
    <#
    .SYNOPSIS
    DNS Records have been set up to support DKIM
    #>
    param($Tenant)

    try {
        $DkimConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoDkimSigningConfig'
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $DkimConfig -or -not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'DNS Records have been set up to support DKIM' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'DKIM'
            return
        }

        $FailedDomains = [System.Collections.Generic.List[object]]::new()
        $PassedDomains = [System.Collections.Generic.List[object]]::new()
        $CustomDomains = $AcceptedDomains | Where-Object { $_.DomainName -notlike '*onmicrosoft.com' }

        foreach ($Domain in $CustomDomains) {
            $DkimRecord = $DkimConfig | Where-Object { $_.Domain -eq $Domain.DomainName }

            if ($DkimRecord -and $DkimRecord.Selector1CNAME -and $DkimRecord.Selector2CNAME) {
                $PassedDomains.Add($Domain) | Out-Null
            } else {
                $FailedDomains.Add($Domain) | Out-Null
            }
        }

        if ($FailedDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All custom domains have DKIM DNS records configured.`n`n"
            $Result += "**Compliant Domains:** $($PassedDomains.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedDomains.Count) custom domains do not have DKIM DNS records configured.`n`n"
            $Result += "**Non-Compliant Domains:** $($FailedDomains.Count)`n`n"
            $Result += "| Domain Name |`n"
            $Result += "|------------|`n"
            foreach ($Domain in $FailedDomains) {
                $Result += "| $($Domain.DomainName) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'DNS Records have been set up to support DKIM' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'DKIM'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'DNS Records have been set up to support DKIM' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'DKIM'
    }
}

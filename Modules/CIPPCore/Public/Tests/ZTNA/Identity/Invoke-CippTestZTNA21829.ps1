function Invoke-CippTestZTNA21829 {
    <#
    .SYNOPSIS
    Use cloud authentication
    #>
    param($Tenant)
    #Tested
    $TestId = 'ZTNA21829'

    try {
        # Get domains
        $Domains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Domains'

        if (-not $Domains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Use cloud authentication' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Access control'
            return
        }

        $FederatedDomains = $Domains | Where-Object { $_.authenticationType -eq 'Federated' }
        $Passed = if ($FederatedDomains.Count -eq 0) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = "All domains are using cloud authentication.`n`n"
        } else {
            $ResultMarkdown = "Federated authentication is in use.`n`n"

            $ResultMarkdown += "`n## List of federated domains`n`n"
            $ResultMarkdown += "| Domain Name |`n"
            $ResultMarkdown += "| :--- |`n"
            foreach ($Domain in $FederatedDomains) {
                $ResultMarkdown += "| $($Domain.id) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Use cloud authentication' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Access control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Use cloud authentication' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Access control'
    }
}

function Invoke-CippTestZTNA21861 {
    <#
    .SYNOPSIS
    All high-risk users are triaged
    #>
    param($Tenant)

    $TestId = 'ZTNA21861'
    #Tested
    try {
        # Get risky users from cache
        $RiskyUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RiskyUsers'

        if (-not $RiskyUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'All high-risk users are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'
            return
        }

        # Filter for untriaged high-risk users (atRisk state with High risk level)
        $UntriagedHighRiskUsers = $RiskyUsers | Where-Object { $_.riskState -eq 'atRisk' -and $_.riskLevel -eq 'high' }

        $Passed = if ($UntriagedHighRiskUsers.Count -eq 0) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = '✅ All high-risk users are properly triaged in Entra ID Protection.'
        } else {
            $ResultMarkdown = "❌ Found **$($UntriagedHighRiskUsers.Count)** untriaged high-risk users in Entra ID Protection.`n`n"
            $ResultMarkdown += "## Untriaged High-Risk Users`n`n"
            $ResultMarkdown += "| User | Risk level | Last updated | Risk detail |`n"
            $ResultMarkdown += "| :--- | :--- | :--- | :--- |`n"

            foreach ($User in $UntriagedHighRiskUsers) {
                $UserPrincipalName = if ($User.userPrincipalName) { $User.userPrincipalName } else { $User.id }
                $RiskLevel = switch ($User.riskLevel) {
                    'high' { '🔴 High' }
                    'medium' { '🟡 Medium' }
                    'low' { '🟢 Low' }
                    default { $User.riskLevel }
                }
                $RiskDate = $User.riskLastUpdatedDateTime
                $RiskDetail = $User.riskDetail

                $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($User.id)"
                $ResultMarkdown += "| [$UserPrincipalName]($PortalLink) | $RiskLevel | $RiskDate | $RiskDetail |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'All high-risk users are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'All high-risk users are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'
    }
}

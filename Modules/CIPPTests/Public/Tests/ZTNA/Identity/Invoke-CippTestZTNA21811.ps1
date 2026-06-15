function Invoke-CippTestZTNA21811 {
    <#
    .SYNOPSIS
    Password expiration is disabled
    #>
    param($Tenant)
    #Tested
    try {
        $domains = Get-CIPPTestData -TenantFilter $Tenant -Type 'Domains'

        if (-not $domains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21811' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Password expiration is disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential Management'
            return
        }

        $misconfiguredDomains = $domains | Where-Object { $_.passwordValidityPeriodInDays -ne 2147483647 }

        $users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        $misconfiguredUsers = @()
        if ($users) {
            $misconfiguredUsers = foreach ($user in $users) {
                $userDomain = $user.userPrincipalName.Split('@')[-1]
                $domainPolicy = $misconfiguredDomains | Where-Object { $_.id -eq $userDomain }
                if (($user.passwordPolicies -notlike '*DisablePasswordExpiration*') -and ($domainPolicy)) {
                    [PSCustomObject]@{
                        id                     = $user.id
                        displayName            = $user.displayName
                        userPrincipalName      = $user.userPrincipalName
                        passwordPolicies       = $user.passwordPolicies
                        DomainPasswordValidity = $domainPolicy.passwordValidityPeriodInDays
                    }
                }
            }
        }

        if ($misconfiguredDomains -or $misconfiguredUsers) {
            $passed = 'Failed'
            $testResultMarkdown = 'Found domains or users with password expiration still enabled.'
        } else {
            $passed = 'Passed'
            $testResultMarkdown = 'Password expiration is properly disabled across all domains and users.'
        }

        if ($misconfiguredDomains) {
            $reportTitle1 = 'Domains with password expiration enabled'
            $mdInfo1 = [System.Text.StringBuilder]::new("`n## $reportTitle1`n`n")
            $null = $mdInfo1.Append("| Domain Name | Password Validity Interval |`n")
            $null = $mdInfo1.Append("| :---------- | :------------------------- |`n")

            foreach ($domain in $misconfiguredDomains) {
                $null = $mdInfo1.Append("| $($domain.id) | $($domain.passwordValidityPeriodInDays) |`n")
            }

            $testResultMarkdown = $testResultMarkdown + $mdInfo1
        }

        if ($misconfiguredUsers) {
            $reportTitle2 = 'Users with password expiration enabled'
            $mdInfo2 = [System.Text.StringBuilder]::new("`n## $reportTitle2`n`n")
            $null = $mdInfo2.Append("| Display Name | User Principal Name | User Password Expiration setting | Domain Password Expiration setting |`n")
            $null = $mdInfo2.Append("| :----------- | :------------------ | :------------------------------- | :--------------------------------- |`n")

            foreach ($misconfiguredUser in $misconfiguredUsers) {
                $displayName = $misconfiguredUser.displayName
                $userPrincipalName = $misconfiguredUser.userPrincipalName
                $userPasswordExpiration = $misconfiguredUser.passwordPolicies
                $domainPasswordExpiration = $misconfiguredUser.DomainPasswordValidity
                $null = $mdInfo2.Append("| $displayName | $userPrincipalName | $userPasswordExpiration | $domainPasswordExpiration |`n")
            }

            $testResultMarkdown = $testResultMarkdown + $mdInfo2
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21811' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'Medium' -Name 'Password expiration is disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21811' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Password expiration is disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential Management'
    }
}

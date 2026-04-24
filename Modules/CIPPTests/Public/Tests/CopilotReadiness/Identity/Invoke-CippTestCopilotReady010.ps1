function Invoke-CippTestCopilotReady010 {
    <#
    .SYNOPSIS
    All licensed users have MFA registered (security prerequisite for Copilot rollout)
    #>
    param($Tenant)

    # MFA is a security baseline requirement before rolling out Copilot. Copilot has broad access
    # to tenant data; ensuring accounts are MFA-protected reduces risk of compromised accounts
    # being used to extract information via Copilot. Pass if 100% of licensed active users
    # have isMfaRegistered = true in their registration details.

    try {
        $UserRegistrationDetails = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $AllUsers = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $UserRegistrationDetails -or -not $AllUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady010' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No MFA registration or user data found in database. Data collection may not yet have run for this tenant.' -Risk 'High' -Name 'All licensed users have MFA registered' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        # Build lookup by UPN for matching
        $RegLookup = @{}
        foreach ($Reg in ($UserRegistrationDetails | Where-Object { $_.userPrincipalName })) {
            $RegLookup[$Reg.userPrincipalName.ToLower()] = $Reg
        }

        $LicensedUsers = @($AllUsers | Where-Object {
                $_.userPrincipalName -and $_.accountEnabled -eq $true -and
                ($_.assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' })
            })

        if ($LicensedUsers.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady010' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No licensed active users found in the tenant.' -Risk 'High' -Name 'All licensed users have MFA registered' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        $NotRegistered = [System.Collections.Generic.List[string]]::new()
        $RegisteredCount = 0

        foreach ($User in $LicensedUsers) {
            $Reg = $RegLookup[$User.userPrincipalName.ToLower()]
            if ($Reg -and $Reg.isMfaRegistered -eq $true) {
                $RegisteredCount++
            } else {
                $NotRegistered.Add($User.userPrincipalName)
            }
        }

        $Total = $LicensedUsers.Count
        $RegisteredPercent = [math]::Round(($RegisteredCount / $Total) * 100, 1)

        if ($NotRegistered.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All **$Total licensed users** have MFA registered — the tenant meets the MFA security baseline for Copilot deployment."
        } else {
            $Status = 'Failed'
            $Result = "**$($NotRegistered.Count) of $Total licensed users ($([math]::Round(($NotRegistered.Count / $Total) * 100, 1))%)** do not have MFA registered.`n`n"
            $Result += 'MFA is a security baseline requirement before deploying Copilot. Accounts without MFA present elevated risk when Copilot has access to tenant data.`n`n'
            $Result += "Remediate by enforcing MFA via Conditional Access or per-user MFA, and requiring users to register via [aka.ms/mfasetup](https://aka.ms/mfasetup).`n`n"
            if ($NotRegistered.Count -le 20) {
                $Result += "**Users without MFA registered:**`n"
                foreach ($Upn in $NotRegistered) { $Result += "- $Upn`n" }
            } else {
                $Result += "**$($NotRegistered.Count) users** do not have MFA registered."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady010' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'All licensed users have MFA registered' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady010: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady010' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'All licensed users have MFA registered' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
    }
}

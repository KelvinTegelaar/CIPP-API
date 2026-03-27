function Invoke-CippTestCopilotReady006 {
    <#
    .SYNOPSIS
    Users are actively using OneDrive/SharePoint (Copilot value indicator)
    #>
    param($Tenant)

    # Copilot adds significant value when users actively store and collaborate on files.
    # The MS readiness report flags "Uses Office docs" (OneDrive/SharePoint activity in past 30 days)
    # as a key indicator of which users will benefit most from Copilot.
    # Threshold: at least 50% of users with activity in the past 7 days (D7 cache window)
    $ActivityThresholdPercent = 50

    try {
        $OneDriveData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'OneDriveUsage'

        if (-not $OneDriveData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady006' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No OneDrive usage data found in database. Data collection may not yet have run for this tenant.' -Risk 'Medium' -Name 'Users are actively using OneDrive/SharePoint' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        # Filter out count rows
        $Users = @($OneDriveData | Where-Object { $_.ownerPrincipalName -and $_.ownerPrincipalName -ne '' })

        if ($Users.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady006' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No user-level OneDrive usage data found. This may indicate no licensed OneDrive users in the tenant.' -Risk 'Medium' -Name 'Users are actively using OneDrive/SharePoint' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $ActiveUsers = @($Users | Where-Object { $_.isDeleted -ne $true -and ($_.fileCount -gt 0 -or $_.activeFileCount -gt 0) })
        $InactiveUsers = @($Users | Where-Object { $_.isDeleted -ne $true -and $_.fileCount -eq 0 -and $_.activeFileCount -eq 0 })
        $TotalUsers = $Users.Count
        $ActiveCount = $ActiveUsers.Count
        $ActivityPercent = if ($TotalUsers -gt 0) { [math]::Round(($ActiveCount / $TotalUsers) * 100, 1) } else { 0 }

        if ($ActivityPercent -ge $ActivityThresholdPercent) {
            $Status = 'Passed'
            $Result = "**$ActiveCount of $TotalUsers users ($ActivityPercent%)** have active OneDrive/SharePoint file storage — above the $ActivityThresholdPercent% threshold.`n`n"
            $Result += "These users are strong candidates for Copilot, which provides the most value when users actively collaborate on files in Microsoft 365."
        } else {
            $Status = 'Failed'
            $Result = "Only **$ActiveCount of $TotalUsers users ($ActivityPercent%)** have active OneDrive/SharePoint usage — below the $ActivityThresholdPercent% threshold.`n`n"
            $Result += "Copilot delivers the most value when users regularly store and collaborate on files in OneDrive and SharePoint. "
            $Result += "Consider driving OneDrive adoption before or alongside a Copilot rollout.`n`n"
            if ($InactiveUsers.Count -gt 0 -and $InactiveUsers.Count -le 20) {
                $Result += "**Inactive users:**`n"
                foreach ($User in $InactiveUsers) {
                    $Result += "- $($User.ownerDisplayName) ($($User.ownerPrincipalName))`n"
                }
            } elseif ($InactiveUsers.Count -gt 20) {
                $Result += "**$($InactiveUsers.Count) inactive users** — too many to list individually."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady006' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users are actively using OneDrive/SharePoint' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady006: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady006' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users are actively using OneDrive/SharePoint' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}

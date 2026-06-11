function Invoke-CippTestCopilotReady003 {
    <#
    .SYNOPSIS
    Users have Microsoft 365 desktop apps activated (Copilot prerequisite)
    #>
    param($Tenant)

    # Copilot in Word, Excel, PowerPoint, and Outlook requires the M365 desktop client (Windows or Mac).
    # The MS readiness assessment checks "Office Activations" — whether users have activated
    # M365 Apps on a desktop platform. Users with only web or mobile activations cannot use
    # Copilot's in-app document generation and editing features.
    # We cross-reference the activation report with licensed users (assignedPlans service 'MicrosoftOffice')
    # so that users who have never opened the app at all are counted as unactivated, not silently omitted.
    # Threshold: at least 70% of M365 Apps licensed users have a desktop (Windows/Mac) activation.
    $DesktopThresholdPercent = 70

    try {
        $ActivationData = Get-CIPPTestData -TenantFilter $Tenant -Type 'OfficeActivations'
        $AllUsers = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $ActivationData -and -not $AllUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady003' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Office activation or user data found in database. Data collection may not yet have run for this tenant.' -Risk 'High' -Name 'Users have M365 desktop apps activated' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        # Build a lookup of activation data keyed by UPN for fast cross-referencing
        $ActivationLookup = @{}
        if ($ActivationData) {
            foreach ($Entry in ($ActivationData | Where-Object { $_.userPrincipalName -and $_.userPrincipalName -ne '' })) {
                $ActivationLookup[$Entry.userPrincipalName.ToLower()] = $Entry
            }
        }

        # Filter Users cache to those with an active M365 Apps (desktop) license plan.
        # assignedPlans entries with service 'MicrosoftOffice' and capabilityStatus 'Enabled'
        # indicate the user holds a license that includes M365 desktop applications.
        $LicensedUsers = @($AllUsers | Where-Object {
            $_.userPrincipalName -and $_.accountEnabled -eq $true -and
            ($_.assignedPlans | Where-Object { $_.service -eq 'MicrosoftOffice' -and $_.capabilityStatus -eq 'Enabled' })
        })

        if ($LicensedUsers.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady003' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No users with an active M365 Apps license were found. Desktop activation check is not applicable.' -Risk 'High' -Name 'Users have M365 desktop apps activated' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        # For each licensed user, check if they have a desktop activation in the activation report.
        # Users absent from the report entirely are counted as unactivated.
        # The Graph API returns activation counts nested inside userActivationCounts[] per product type,
        # so we sum windows/mac across all product types to get the total desktop activation count.
        $NoDesktopUsers = [System.Collections.Generic.List[object]]::new()
        $DesktopCount = 0
        foreach ($User in $LicensedUsers) {
            $Activation = $ActivationLookup[$User.userPrincipalName.ToLower()]
            $TotalWindows = 0
            $TotalMac = 0
            $TotalAndroid = 0
            $TotalIos = 0
            if ($Activation.userActivationCounts) {
                $TotalWindows = ($Activation.userActivationCounts | Measure-Object -Property windows -Sum).Sum
                $TotalMac = ($Activation.userActivationCounts | Measure-Object -Property mac -Sum).Sum
                $TotalAndroid = ($Activation.userActivationCounts | Measure-Object -Property android -Sum).Sum
                $TotalIos = ($Activation.userActivationCounts | Measure-Object -Property ios -Sum).Sum
            }
            if ($Activation -and (($TotalWindows + $TotalMac) -gt 0)) {
                $DesktopCount++
            } else {
                $NoDesktopUsers.Add([pscustomobject]@{
                    displayName       = $User.displayName
                    userPrincipalName = $User.userPrincipalName
                    android           = if ($Activation) { $TotalAndroid } else { 0 }
                    ios               = if ($Activation) { $TotalIos } else { 0 }
                    neverActivated    = ($null -eq $Activation)
                })
            }
        }

        $TotalUsers = $LicensedUsers.Count
        $DesktopPercent = if ($TotalUsers -gt 0) { [math]::Round(($DesktopCount / $TotalUsers) * 100, 1) } else { 0 }

        if ($DesktopPercent -ge $DesktopThresholdPercent) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("**$DesktopCount of $TotalUsers licensed users ($DesktopPercent%)** have Microsoft 365 Apps activated on a desktop platform (Windows or Mac) — above the $DesktopThresholdPercent% threshold.`n`n")
            $null = $Result.Append("These users can access Copilot features in desktop Word, Excel, PowerPoint, and Outlook.")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("Only **$DesktopCount of $TotalUsers licensed users ($DesktopPercent%)** have Microsoft 365 Apps activated on a desktop platform — below the $DesktopThresholdPercent% threshold.`n`n")
            $null = $Result.Append("Copilot in Word, Excel, PowerPoint, and Outlook requires the M365 desktop application. ")
            $null = $Result.Append("Users with only web or mobile activations, or who have never activated at all, cannot use Copilot's in-document features.`n`n")
            if ($NoDesktopUsers.Count -gt 0 -and $NoDesktopUsers.Count -le 20) {
                $null = $Result.Append("**Users without desktop activation:**`n")
                foreach ($User in $NoDesktopUsers) {
                    if ($User.neverActivated) {
                        $PlatformStr = ' (never activated)'
                    } else {
                        $Platforms = @()
                        if ([int]($User.android ?? 0) -gt 0 -or [int]($User.ios ?? 0) -gt 0) { $Platforms += 'Mobile' }
                        $PlatformStr = if ($Platforms) { " ($(($Platforms -join ', ')) only)" } else { ' (no activations)' }
                    }
                    $null = $Result.Append("- $($User.displayName) ($($User.userPrincipalName))$PlatformStr`n")
                }
            } elseif ($NoDesktopUsers.Count -gt 20) {
                $NeverActivated = @($NoDesktopUsers | Where-Object { $_.neverActivated }).Count
                $null = $Result.Append("**$($NoDesktopUsers.Count) users** have no desktop M365 Apps activation")
                if ($NeverActivated -gt 0) { $null = $Result.Append(" ($NeverActivated have never activated on any platform)") }
                $null = $Result.Append(".`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady003' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Users have M365 desktop apps activated' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady003: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady003' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Users have M365 desktop apps activated' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
    }
}

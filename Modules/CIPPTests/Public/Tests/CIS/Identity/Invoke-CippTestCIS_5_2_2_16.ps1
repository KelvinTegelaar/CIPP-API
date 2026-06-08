function Invoke-CippTestCIS_5_2_2_16 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.2.16) - Token Protection is enforced for session tokens
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_16' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'Token Protection is enforced for session tokens' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Session Management'
            return
        }

        # Office 365 Exchange Online, SharePoint Online and Microsoft Teams Services app GUIDs
        $ExchangeOnline = '00000002-0000-0ff1-ce00-000000000000'
        $SharePointOnline = '00000003-0000-0ff1-ce00-000000000000'
        $TeamsServices = 'cc15fd57-2c6c-4117-a88c-83b1d56b4bbe'

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeUsers -notcontains 'None' -and
            $_.conditions.applications.includeApplications -contains $ExchangeOnline -and
            $_.conditions.applications.includeApplications -contains $SharePointOnline -and
            $_.conditions.applications.includeApplications -contains $TeamsServices -and
            $_.conditions.platforms.includePlatforms -contains 'windows' -and
            $_.conditions.clientAppTypes -contains 'mobileAppsAndDesktopClients' -and
            $_.sessionControls.secureSignInSession -and
            $_.sessionControls.secureSignInSession.isEnabled -eq $true
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies enforce Token Protection for sign-in sessions:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy enforces Token Protection (secure sign-in session) for Exchange Online, SharePoint Online and Teams on Windows desktop/mobile clients.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_16' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Token Protection is enforced for session tokens' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Session Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_16' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Token Protection is enforced for session tokens' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Session Management'
    }
}

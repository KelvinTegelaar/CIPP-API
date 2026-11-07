function Invoke-CippTestZTNA21801 {
    <#
    .SYNOPSIS
    Users have strong authentication methods configured
    #>
    param($Tenant)

    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA21801' -TenantFilter $Tenant -Preset Entra -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21801' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Entra ID P1. Required capabilities: AAD_PREMIUM, AAD_PREMIUM_P2.' -Risk 'Medium' -Name 'Users have strong authentication methods configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'
            return
        }

        $UserRegistrationDetails = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $UserRegistrationDetails -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21801' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Users have strong authentication methods configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'
            return
        }

        $PhishResistantMethods = @('passKeyDeviceBound', 'passKeyDeviceBoundAuthenticator', 'windowsHelloForBusiness')

        # Create hashtable for O(1) user lookup instead of O(n) Where-Object searches
        $UserLookup = @{}
        foreach ($user in $Users) {
            if ($user.accountEnabled) {
                $UserLookup[$user.id] = $user
            }
        }

        $results = foreach ($regDetail in $UserRegistrationDetails) {
            # Fast O(1) lookup instead of Where-Object
            if (-not $UserLookup.ContainsKey($regDetail.id)) {
                continue
            }

            $matchingUser = $UserLookup[$regDetail.id]
            $hasPhishResistant = $false

            if ($regDetail.methodsRegistered) {
                foreach ($method in $PhishResistantMethods) {
                    if ($regDetail.methodsRegistered -contains $method) {
                        $hasPhishResistant = $true
                        break
                    }
                }
            }

            [PSCustomObject]@{
                id                           = $regDetail.id
                displayName                  = $regDetail.userDisplayName
                phishResistantAuthMethod     = $hasPhishResistant
                lastSuccessfulSignInDateTime = $matchingUser.signInActivity.lastSuccessfulSignInDateTime
            }
        }

        $results = @($results)
        $totalUserCount = $results.Count
        $phishResistantUserCount = $results.Where({ $_.phishResistantAuthMethod }).Count
        $phishableUsers = @($results.Where({ !$_.phishResistantAuthMethod }))

        $passed = $totalUserCount -eq $phishResistantUserCount

        $testResultMarkdown = if ($passed) {
            "Validated that all users have registered phishing resistant authentication methods.`n`n%TestResult%"
        } else {
            "Found users that have not yet registered phishing resistant authentication methods`n`n%TestResult%"
        }

        $mdInfo = [System.Text.StringBuilder]::new("## Users strong authentication methods`n`n")
        $null = $mdInfo.Append("Total users assessed: $totalUserCount`n`n")
        $null = $mdInfo.Append("Users with phishing-resistant authentication methods: $phishResistantUserCount`n`n")
        $null = $mdInfo.Append("Users without phishing-resistant authentication methods: $($phishableUsers.Count)`n`n")

        $reportedPhishableUsers = @($phishableUsers | Sort-Object displayName, id).Where({ $true }, 'First', 50)
        if ($reportedPhishableUsers.Count -gt 0) {
            $null = $mdInfo.Append("| User | Last sign in | Phishing resistant method registered |`n")
            $null = $mdInfo.Append("| :--- | :--- | :---: |`n")
            $userLinkFormat = 'https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/UserAuthMethods/userId/{0}/hidePreviewBanner~/true'
            foreach ($user in $reportedPhishableUsers) {
                $lastSignInDate = if ($user.lastSuccessfulSignInDateTime) { (Get-Date $user.lastSuccessfulSignInDateTime -Format 'yyyy-MM-dd') } else { 'Never' }
                $null = $mdInfo.Append("|[$($user.displayName)]($($userLinkFormat -f $user.id))| $lastSignInDate | ❌ |`n")
            }
            $omittedUserCount = $phishableUsers.Count - $reportedPhishableUsers.Count
            if ($omittedUserCount -gt 0) {
                $null = $mdInfo.Append("`nShowing 50 of $($phishableUsers.Count) users without phishing-resistant authentication methods; $omittedUserCount more omitted.`n")
            }
        }

        $testResultMarkdown = $testResultMarkdown.Replace('%TestResult%', $mdInfo.ToString())

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21801' -TestType 'Identity' -Status $(if ($passed) { 'Passed' } else { 'Failed' }) -ResultMarkdown $testResultMarkdown -Risk 'Medium' -Name 'Users have strong authentication methods configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21801' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users have strong authentication methods configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'
    }
}

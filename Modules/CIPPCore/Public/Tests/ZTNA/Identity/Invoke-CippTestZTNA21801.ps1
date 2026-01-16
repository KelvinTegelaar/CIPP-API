function Invoke-CippTestZTNA21801 {
    <#
    .SYNOPSIS
    Users have strong authentication methods configured
    #>
    param($Tenant)

    try {
        $UserRegistrationDetails = New-CIPPDbRequest -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $Users = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        if (-not $UserRegistrationDetails -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21801' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Users have strong authentication methods configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'
            return
        }

        $PhishResistantMethods = @('passKeyDeviceBound', 'passKeyDeviceBoundAuthenticator', 'windowsHelloForBusiness')

        $results = $UserRegistrationDetails | Where-Object {
            $userId = $_.id
            $matchingUser = $Users | Where-Object { $_.id -eq $userId -and $_.accountEnabled }
            $matchingUser
        } | ForEach-Object {
            $regDetail = $_
            $matchingUser = $Users | Where-Object { $_.id -eq $regDetail.id }
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

        $totalUserCount = $results.Length
        $phishResistantUsers = $results | Where-Object { $_.phishResistantAuthMethod }
        $phishableUsers = $results | Where-Object { !$_.phishResistantAuthMethod }

        $phishResistantUserCount = $phishResistantUsers.Length

        $passed = $totalUserCount -eq $phishResistantUserCount

        $testResultMarkdown = if ($passed) {
            "Validated that all users have registered phishing resistant authentication methods.`n`n%TestResult%"
        } else {
            "Found users that have not yet registered phishing resistant authentication methods`n`n%TestResult%"
        }

        $mdInfo = "## Users strong authentication methods`n`n"

        if ($passed) {
            $mdInfo = "All users have registered phishing resistant authentication methods.`n`n"
        } else {
            $mdInfo = "Found users that have not registered phishing resistant authentication methods.`n`n"
        }

        $mdInfo = $mdInfo + "| User | Last sign in | Phishing resistant method registered |`n"
        $mdInfo = $mdInfo + "| :--- | :--- | :---: |`n"

        $userLinkFormat = 'https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/UserAuthMethods/userId/{0}/hidePreviewBanner~/true'

        $mdLines = @($phishableUsers | Sort-Object displayName | ForEach-Object {
                $userLink = $userLinkFormat -f $_.id
                $lastSignInDate = if ($_.lastSuccessfulSignInDateTime) { (Get-Date $_.lastSuccessfulSignInDateTime -Format 'yyyy-MM-dd') } else { 'Never' }
                "|[$($_.displayName)]($userLink)| $lastSignInDate | ❌ |`n"
            })
        $mdInfo = $mdInfo + ($mdLines -join '')

        $mdLines = @($phishResistantUsers | Sort-Object displayName | ForEach-Object {
                $userLink = $userLinkFormat -f $_.id
                $lastSignInDate = if ($_.lastSuccessfulSignInDateTime) { (Get-Date $_.lastSuccessfulSignInDateTime -Format 'yyyy-MM-dd') } else { 'Never' }
                "|[$($_.displayName)]($userLink)| $lastSignInDate | ✅ |`n"
            })
        $mdInfo = $mdInfo + ($mdLines -join '')

        $testResultMarkdown = $testResultMarkdown -replace '%TestResult%', $mdInfo

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21801' -TestType 'Identity' -Status $(if ($passed) { 'Passed' } else { 'Failed' }) -ResultMarkdown $testResultMarkdown -Risk 'Medium' -Name 'Users have strong authentication methods configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21801' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users have strong authentication methods configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential Management'
    }
}

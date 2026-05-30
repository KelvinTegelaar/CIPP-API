function Invoke-CippTestZTNA21782 {
    <#
    .SYNOPSIS
    Privileged accounts have phishing-resistant methods registered
    #>
    param($Tenant)

    try {
        $UserRegistrationDetails = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $RoleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignments'

        if (-not $UserRegistrationDetails -or -not $RoleAssignments) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21782' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Privileged accounts have phishing-resistant methods registered' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $PhishResistantMethods = @('passKeyDeviceBound', 'passKeyDeviceBoundAuthenticator', 'windowsHelloForBusiness')

        $RoleAssignmentsByPrincipal = $RoleAssignments | Group-Object principalId -AsHashTable -AsString
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($user in $UserRegistrationDetails) {
            if (-not $RoleAssignmentsByPrincipal.ContainsKey($user.id)) { continue }
            $userRoles = $RoleAssignmentsByPrincipal[$user.id]
            $hasPhishResistant = $false
            if ($user.methodsRegistered) {
                foreach ($method in $PhishResistantMethods) {
                    if ($user.methodsRegistered -contains $method) {
                        $hasPhishResistant = $true
                        break
                    }
                }
            }
            $results.Add([PSCustomObject]@{
                id                       = $user.id
                userDisplayName          = $user.userDisplayName
                roleDisplayName          = ($userRoles.roleDefinitionName -join ', ')
                methodsRegistered        = $user.methodsRegistered
                phishResistantAuthMethod = $hasPhishResistant
            })
        }

        $totalUserCount = $results.Count
        $phishResistantPrivUsers = $results.Where({ $_.phishResistantAuthMethod })
        $phishablePrivUsers = $results.Where({ !$_.phishResistantAuthMethod })

        $phishResistantPrivUserCount = $phishResistantPrivUsers.Count

        $passed = $totalUserCount -eq $phishResistantPrivUserCount

        $testResultMarkdown = if ($passed) {
            "Validated that all privileged users have registered phishing resistant authentication methods.`n`n%TestResult%"
        } else {
            "Found privileged users that have not yet registered phishing resistant authentication methods`n`n%TestResult%"
        }

        $mdInfo = "## Privileged users`n`n"

        if ($passed) {
            $mdInfo = "All privileged users have registered phishing resistant authentication methods.`n`n"
        } else {
            $mdInfo = "Found privileged users that have not registered phishing resistant authentication methods.`n`n"
        }

        $mdInfo = $mdInfo + "| User | Role Name | Phishing resistant method registered |`n"
        $mdInfo = $mdInfo + "| :--- | :--- | :---: |`n"

        $userLinkFormat = 'https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/UserAuthMethods/userId/{0}/hidePreviewBanner~/true'

        $mdLines = @($phishablePrivUsers | Sort-Object userDisplayName | ForEach-Object {
                $userLink = $userLinkFormat -f $_.id
                "|[$($_.userDisplayName)]($userLink)| $($_.roleDisplayName) | ❌ |`n"
            })
        $mdInfo = $mdInfo + ($mdLines -join '')

        $mdLines = @($phishResistantPrivUsers | Sort-Object userDisplayName | ForEach-Object {
                $userLink = $userLinkFormat -f $_.id
                "|[$($_.userDisplayName)]($userLink)| $($_.roleDisplayName) | ✅ |`n"
            })
        $mdInfo = $mdInfo + ($mdLines -join '')

        $testResultMarkdown = $testResultMarkdown -replace '%TestResult%', $mdInfo

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21782' -TestType 'Identity' -Status $(if ($passed) { 'Passed' } else { 'Failed' }) -ResultMarkdown $testResultMarkdown -Risk 'High' -Name 'Privileged accounts have phishing-resistant methods registered' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21782' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Privileged accounts have phishing-resistant methods registered' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}

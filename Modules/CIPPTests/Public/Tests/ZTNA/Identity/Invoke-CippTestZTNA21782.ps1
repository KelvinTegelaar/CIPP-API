function Invoke-CippTestZTNA21782 {
    <#
    .SYNOPSIS
    Privileged accounts have phishing-resistant methods registered
    #>
    param($Tenant)

    try {
        $UserRegistrationDetails = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'

        if ($null -eq $UserRegistrationDetails -or $null -eq $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21782' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (UserRegistrationDetails or Roles) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Privileged accounts have phishing-resistant methods registered' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $PhishResistantMethods = @('passKeyDeviceBound', 'passKeyDeviceBoundAuthenticator', 'windowsHelloForBusiness')

        $PrivilegedRoleIds = [System.Collections.Generic.HashSet[string]]::new()
        $RoleNamesById = @{}
        foreach ($Role in @($Roles.Where({ $_.isPrivileged -eq $true }))) {
            if ($Role.id) {
                [void]$PrivilegedRoleIds.Add([string]$Role.id)
                $RoleNamesById[[string]$Role.id] = $Role.displayName
            }
        }

        $PrivilegedPrincipalsById = @{}
        foreach ($Role in @($Roles.Where({ $_.isPrivileged -eq $true }))) {
            foreach ($Member in @($Role.members)) {
                if (-not $Member.id) { continue }
                $principalId = [string]$Member.id
                if (-not $PrivilegedPrincipalsById.ContainsKey($principalId)) {
                    $PrivilegedPrincipalsById[$principalId] = [System.Collections.Generic.HashSet[string]]::new()
                }
                [void]$PrivilegedPrincipalsById[$principalId].Add($Role.displayName)
            }
        }

        foreach ($Assignment in @($RoleAssignmentScheduleInstances)) {
            if ($Assignment.roleDefinitionId -and $Assignment.assignmentType -eq 'Assigned' -and $null -eq $Assignment.endDateTime -and $PrivilegedRoleIds.Contains([string]$Assignment.roleDefinitionId) -and $Assignment.principalId) {
                $principalId = [string]$Assignment.principalId
                if (-not $PrivilegedPrincipalsById.ContainsKey($principalId)) {
                    $PrivilegedPrincipalsById[$principalId] = [System.Collections.Generic.HashSet[string]]::new()
                }
                $roleName = $RoleNamesById[[string]$Assignment.roleDefinitionId]
                if ($roleName) {
                    [void]$PrivilegedPrincipalsById[$principalId].Add($roleName)
                }
            }
        }

        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($user in $UserRegistrationDetails) {
            if (-not $PrivilegedPrincipalsById.ContainsKey($user.id)) { continue }
            $userRoles = $PrivilegedPrincipalsById[$user.id]
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
                    roleDisplayName          = ($userRoles | Sort-Object | Select-Object -Unique) -join ', '
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

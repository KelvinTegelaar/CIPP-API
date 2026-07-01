function Invoke-CippTestE8_MFA_07 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML2) - Privileged users have a phishing-resistant method registered
    #>
    param($Tenant)

    $TestId = 'E8_MFA_07'
    $Name = 'All privileged users have a phishing-resistant authentication method registered'

    try {
        $Reg = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $Roles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'

        if (-not $Reg -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (UserRegistrationDetails or Roles) not found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'E8 ML2 - MFA'
            return
        }

        $PrivRoleIds = [System.Collections.Generic.HashSet[string]]::new()
        $PrivUserIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Role in @($Roles)) {
            $RoleTemplateId = if ($Role.roleTemplateId) { [string]$Role.roleTemplateId } elseif ($Role.RoletemplateId) { [string]$Role.RoletemplateId } else { $null }
            if ($RoleTemplateId) { [void]$PrivRoleIds.Add($RoleTemplateId) }
            foreach ($M in @($Role.members)) {
                if ($M.id -and $M.'@odata.type' -eq '#microsoft.graph.user') { [void]$PrivUserIds.Add([string]$M.id) }
            }
        }
        foreach ($A in @($RoleAssignmentScheduleInstances)) {
            if ($A.assignmentType -eq 'Assigned' -and $null -eq $A.endDateTime -and $A.principalId -and $PrivRoleIds.Contains([string]$A.roleDefinitionId)) {
                [void]$PrivUserIds.Add([string]$A.principalId)
            }
        }

        if ($PrivUserIds.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No privileged users found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'E8 ML2 - MFA'
            return
        }

        $PhishMethods = @('fido2SecurityKey','windowsHelloForBusiness','x509CertificateSingleFactor','x509CertificateMultiFactor','passKeyDeviceBound','passKeyDeviceBoundAuthenticator','passKeyDeviceBoundWindowsHello')
        $NonCompliant = foreach ($R in $Reg | Where-Object { $PrivUserIds.Contains($_.id) }) {
            $HasPhish = $false
            foreach ($M in $R.methodsRegistered) {
                if ($PhishMethods -contains $M) { $HasPhish = $true; break }
            }
            if (-not $HasPhish) { $R }
        }

        if (-not $NonCompliant) {
            $Status = 'Passed'
            $Result = "All $($PrivUserIds.Count) privileged users have at least one phishing-resistant method registered."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($NonCompliant.Count) of $($PrivUserIds.Count) privileged users have no phishing-resistant method registered:`n`n| UPN | Methods Registered |`n| :-- | :----------------- |`n")
            foreach ($U in ($NonCompliant | Select-Object -First 50)) {
                $null = $Sb.Append("| $($U.userPrincipalName) | $(($U.methodsRegistered) -join ', ') |`n")
            }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'E8 ML2 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'E8 ML2 - MFA'
    }
}

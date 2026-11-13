function Invoke-CippTestZTNA61006 {
    <#
    .SYNOPSIS
    AI administrative roles have assigned principals
    #>
    param($Tenant)

    $TestId = 'ZTNA61006'
    $Name = 'AI administrative roles have assigned principals'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -RequiredCapabilities 'AAD_BASIC' -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Entra ID. Required capabilities: AAD_BASIC, AAD_PREMIUM, AAD_PREMIUM_P2.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Authentication & Access'
            return
        }

        $RoleDefinitions = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleDefinitions'
        $RoleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignments'
        if (-not $RoleDefinitions -or -not $RoleAssignments) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Role definitions or role assignments not found in database. Data collection may not have completed yet.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Authentication & Access'
            return
        }
        $ScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Eligibilities = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleEligibilitySchedules'

        $InScopeRoles = @(
            @{ Name = 'AI Administrator'; Id = 'd2562ede-74db-457e-a7b6-544e236ebb61'; Tier = 'Admin' }
            @{ Name = 'Agent ID Administrator'; Id = 'db506228-d27e-4b7d-95e5-295956d6615f'; Tier = 'Admin' }
            @{ Name = 'Agent ID Developer'; Id = 'adb2368d-a9be-41b5-8667-d96778e081b0'; Tier = 'Admin' }
            @{ Name = 'Agent Registry Administrator'; Id = '6b942400-691f-4bf0-9d12-d8a254a2baf5'; Tier = 'Admin' }
            @{ Name = 'Application Administrator'; Id = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'; Tier = 'Admin' }
            @{ Name = 'Compliance Administrator'; Id = '17315797-102d-40b4-93e0-432062caca18'; Tier = 'Admin' }
            @{ Name = 'Compliance Data Administrator'; Id = 'e6d1a23a-da11-4be4-9570-befc86d067a7'; Tier = 'Admin' }
            @{ Name = 'Conditional Access Administrator'; Id = 'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9'; Tier = 'Admin' }
            @{ Name = 'Global Reader'; Id = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'; Tier = 'Reader' }
            @{ Name = 'Global Secure Access Administrator'; Id = 'ac434307-12b9-4fa1-a708-88bf58caabc1'; Tier = 'Admin' }
            @{ Name = 'Identity Governance Administrator'; Id = '45d8d3c5-c802-45c6-b32a-1d70b5e1e86e'; Tier = 'Admin' }
            @{ Name = 'Intune Administrator'; Id = '3a2c62db-5318-420d-8d74-23affee5d9d5'; Tier = 'Admin' }
            @{ Name = 'Power Platform Administrator'; Id = '11648597-926c-4cf3-9c36-bcebb0ba8dcc'; Tier = 'Admin' }
            @{ Name = 'Security Administrator'; Id = '194ae4cb-b126-40b2-bd5b-6091b380977d'; Tier = 'Admin' }
            @{ Name = 'Security Operator'; Id = '5f2222b1-57c3-48ba-8ad5-d4759f1fde6f'; Tier = 'Admin' }
            @{ Name = 'Security Reader'; Id = '5d6b6bb7-de71-4623-b4af-96380a352509'; Tier = 'Reader' }
            @{ Name = 'SharePoint Administrator'; Id = 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c'; Tier = 'Admin' }
        )
        $InScopeIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($InScopeRoles.Id), [System.StringComparer]::OrdinalIgnoreCase)
        $PresentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Definition in $RoleDefinitions) { if ($InScopeIds.Contains([string]$Definition.id)) { [void]$PresentIds.Add([string]$Definition.id) } }

        # Assigned PIM instances exclude current activations, so an activated eligible principal is not counted twice.
        $Assignments = @(
            foreach ($Row in $ScheduleInstances) { if ($Row.assignmentType -eq 'Assigned' -and $InScopeIds.Contains([string]$Row.roleDefinitionId)) { $Row } }
            foreach ($Row in $RoleAssignments) { if ($InScopeIds.Contains([string]$Row.roleDefinitionId)) { $Row } }
            foreach ($Row in $Eligibilities) { if ($InScopeIds.Contains([string]$Row.roleDefinitionId)) { $Row } }
        )
        $GroupIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Row in $Assignments) {
            if ($Row.principal.'@odata.type' -eq '#microsoft.graph.group') { [void]$GroupIds.Add([string]$Row.principalId) }
        }
        $NonEmptyGroups = [System.Collections.Generic.HashSet[string]]::new()
        if ($GroupIds.Count -gt 0) {
            Get-CIPPTestData -TenantFilter $Tenant -Type 'Groups' -Fields 'id', 'members' -Stream | ForEach-Object {
                if ($GroupIds.Contains([string]$_.id) -and @($_.members).Count -gt 0) { [void]$NonEmptyGroups.Add([string]$_.id) }
            }
        }

        $TenantScoped = @{}
        $Restricted = @{}
        foreach ($Row in $Assignments) {
            if ($Row.principal.'@odata.type' -eq '#microsoft.graph.group' -and -not $NonEmptyGroups.Contains([string]$Row.principalId)) { continue }
            $RoleId = [string]$Row.roleDefinitionId
            $Bucket = if ($Row.directoryScopeId -eq '/') { $TenantScoped } else { $Restricted }
            if (-not $Bucket[$RoleId]) { $Bucket[$RoleId] = [System.Collections.Generic.HashSet[string]]::new() }
            [void]$Bucket[$RoleId].Add("$($Row.principalId)|$($Row.directoryScopeId)")
        }

        $Evaluated = [System.Collections.Generic.List[object]]::new()
        foreach ($Role in $InScopeRoles) {
            if (-not $PresentIds.Contains($Role.Id)) { continue }
            $TenantCount = if ($TenantScoped[$Role.Id]) { $TenantScoped[$Role.Id].Count } else { 0 }
            $RestrictedCount = if ($Restricted[$Role.Id]) { $Restricted[$Role.Id].Count } else { 0 }
            $Outcome = if ($TenantCount -gt 0) { 'Pass' } elseif ($RestrictedCount -gt 0) { 'Investigate' } else { 'Fail' }
            $Evaluated.Add([PSCustomObject]@{ Name = $Role.Name; Id = $Role.Id; Tier = $Role.Tier; Outcome = $Outcome; TenantCount = $TenantCount; RestrictedCount = $RestrictedCount })
        }

        $AdminFails = $Evaluated.Where({ $_.Tier -eq 'Admin' -and $_.Outcome -eq 'Fail' })
        $ReaderFails = $Evaluated.Where({ $_.Tier -eq 'Reader' -and $_.Outcome -eq 'Fail' })
        $Investigate = $Evaluated.Where({ $_.Outcome -eq 'Investigate' })
        $PassCount = $Evaluated.Where({ $_.Outcome -eq 'Pass' }).Count

        if ($Evaluated.Count -eq 0) {
            $Status = 'Investigate'
            $Headline = 'None of the in-scope AI administrative role definitions were found in this tenant. No roles were evaluated.'
        } elseif ($AdminFails.Count -gt 0) {
            $Status = 'Failed'
            $Headline = 'One or more AI administrative roles in Microsoft Entra have no assigned principal (or only empty role-assignable groups).'
        } elseif ($Investigate.Count -gt 0 -or $ReaderFails.Count -gt 0) {
            $Status = 'Investigate'
            $Headline = 'One or more AI administrative roles are assigned only at administrative-unit or app scope, with no tenant-wide principal. Confirm this matches your delegated-administration model. Reader-tier roles (Global Reader, Security Reader) with no assigned principal also surface here.'
        } else {
            $Status = 'Passed'
            $Headline = 'Every AI administrative role in Microsoft Entra has at least one tenant-scoped assigned principal. Administrators granted through workload-native role systems (Purview role groups, Defender XDR roles, Power Platform roles) are out of scope.'
        }

        $Result = [System.Text.StringBuilder]::new()
        [void]$Result.Append("$Headline`n`n**AI administrative role evaluation summary:**`n`n")
        [void]$Result.Append("* In-scope roles: $($InScopeRoles.Count)`n")
        [void]$Result.Append("* Evaluated (role definition present in tenant): $($Evaluated.Count)`n")
        [void]$Result.Append("* Pass: $PassCount`n* Investigate: $($Investigate.Count)`n* Fail: $($AdminFails.Count + $ReaderFails.Count)`n")

        $NonPass = @(
            foreach ($Role in $Evaluated) { if ($Role.Outcome -eq 'Fail') { $Role } }
            foreach ($Role in $Evaluated) { if ($Role.Outcome -eq 'Investigate') { $Role } }
        )
        if ($NonPass.Count -gt 0) {
            [void]$Result.Append("`n## AI administrative roles with no tenant-scoped assigned principal`n`n")
            [void]$Result.Append("| Role | Tenant-scoped principals | Restricted-scope principals | Tier | Outcome |`n")
            [void]$Result.Append("| :--- | :----------------------- | :-------------------------- | :--- | :------ |`n")
            foreach ($Role in $NonPass) {
                $Link = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RoleMenuBlade/~/AllAssignments/objectId/{0}/roleName/{1}/roleTemplateId/{0}/adminUnitObjectId//customRole~/false/resourceScope/%2F' -f $Role.Id, [System.Uri]::EscapeDataString($Role.Name)
                [void]$Result.Append("| [$($Role.Name)]($Link) | $($Role.TenantCount) | $($Role.RestrictedCount) | $($Role.Tier) | $($Role.Outcome) |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Authentication & Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Authentication & Access'
    }
}

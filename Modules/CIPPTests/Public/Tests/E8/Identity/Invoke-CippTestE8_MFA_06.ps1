function Invoke-CippTestE8_MFA_06 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML2) - Phishing-resistant MFA strength is required for privileged roles
    #>
    param($Tenant)

    $TestId = 'E8_MFA_06'
    $Name = 'Phishing-resistant authentication strength is required for privileged roles'
    # Built-in Phishing-resistant MFA strength
    $PhishResistantId = '00000000-0000-0000-0000-000000000004'

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $Roles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles

        if (-not $CA -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (ConditionalAccessPolicies or Roles) not found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'E8 ML2 - MFA'
            return
        }

        # Conditional Access includeRoles reference role template IDs, not directory role instance IDs.
        $PrivRoleIds = @($Roles | ForEach-Object { if ($_.roleTemplateId) { [string]$_.roleTemplateId } elseif ($_.RoletemplateId) { [string]$_.RoletemplateId } })

        $Match = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeRoles -and
            (@($_.conditions.users.includeRoles) | Where-Object { $_ -in $PrivRoleIds }).Count -gt 0 -and
            $_.grantControls.authenticationStrength -and
            $_.grantControls.authenticationStrength.id -eq $PhishResistantId
        }

        if ($Match) {
            $Status = 'Passed'
            $Result = "$($Match.Count) Conditional Access policy/policies require phishing-resistant MFA for privileged roles:`n`n" +
                (($Match | ForEach-Object { "- $($_.displayName)" }) -join "`n")
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets privileged roles with the built-in *Phishing-resistant MFA* authentication strength.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'E8 ML2 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'E8 ML2 - MFA'
    }
}

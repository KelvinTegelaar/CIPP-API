function Invoke-CippTestCyberIns_03 {
    <#
    .SYNOPSIS
    Cyber Insurance Q3 - MFA is enforced for admin and privileged accounts
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_03'; TestType = 'Identity'; Risk = 'High'; Name = 'MFA is enforced for admin and privileged accounts'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $MFAData = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'
        if (-not $MFAData) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No MFA data found for this tenant. Sync the report data first.'
            return
        }

        $Total = 0
        $Unprotected = [System.Collections.Generic.List[string]]::new()
        foreach ($User in $MFAData) {
            if ($User.IsAdmin -ne $true -or $User.AccountEnabled -ne $true) { continue }
            $Total++
            if ($User.CoveredByCA -notlike 'Enforced*' -and $User.CoveredBySD -ne $true -and $User.PerUser -notin @('Enforced', 'Enabled')) {
                $Unprotected.Add([string]$User.UPN)
            }
        }

        if ($Total -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No enabled accounts holding a directory role were found for this tenant.'
            return
        }

        $Result = [System.Text.StringBuilder]::new("MFA is enforced for **$($Total - $Unprotected.Count) of $Total** enabled accounts that hold a directory role.`n`n")

        $GlobalAdminId = '62e90394-69f5-4237-9190-012177145e10'
        if (Test-CIPPStandardLicense -StandardName 'CyberIns_03' -TenantFilter $Tenant -Preset PIM -SkipLog) {
            $Permanent = 0; $Eligible = 0
            foreach ($Member in (Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $GlobalAdminId)) {
                if ($Member.AssignmentType -eq 'Eligible') { $Eligible++ } elseif ($Member.IsPermanent) { $Permanent++ }
            }
            $Policy = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleManagementPolicies').Where({ $_.scopeId -eq '/' -and $_.scopeType -eq 'DirectoryRole' -and $_.roleDefinitionId -eq $GlobalAdminId }, 'First')[0]
            $Activation = if ($Policy) { $Policy.rules.Where({ $_.id -eq 'Enablement_EndUser_Assignment' }, 'First')[0] }
            $ActivationMfa = if (-not $Activation) { 'Unknown' } elseif ($Activation.enabledRules -contains 'MultiFactorAuthentication') { 'Yes' } else { 'No' }
            $null = $Result.Append("Global Administrator: **$Permanent** permanent and **$Eligible** eligible assignments. Activating the role requires MFA: **$ActivationMfa**.`n`n")
        } else {
            $null = $Result.Append("Privileged Identity Management: not licensed.`n`n")
        }

        if ($Unprotected.Count -gt 0) {
            $null = $Result.Append("Admin accounts without enforced MFA:`n`n")
            foreach ($UPN in $Unprotected) { $null = $Result.Append("- $UPN`n") }
        }

        $Status = if ($Unprotected.Count -eq 0) { 'Passed' } else { 'Failed' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_03: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}

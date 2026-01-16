function Invoke-CippTestZTNA21783 {
    <#
    .SYNOPSIS
    Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods
    #>
    param($Tenant)
    #tested
    try {
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $Roles = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Roles'

        if (-not $CAPolicies -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        $PrivilegedRoles = $Roles | Where-Object { $_.isPrivileged -and $_.isBuiltIn }

        if (-not $PrivilegedRoles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No privileged built-in roles found in tenant' -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        $PhishResistantMethods = @('windowsHelloForBusiness', 'fido2', 'x509CertificateMultiFactor')

        $PhishResistantPolicies = $CAPolicies | Where-Object {
            $_.state -eq 'enabled' -and
            $_.grantControls.authenticationStrength -and
            $_.conditions.users.includeRoles
        }

        $CoveredRoleIds = $PhishResistantPolicies.conditions.users.includeRoles | Select-Object -Unique

        $UnprotectedRoles = $PrivilegedRoles | Where-Object { $_.id -notin $CoveredRoleIds }

        if ($UnprotectedRoles.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($PrivilegedRoles.Count) privileged built-in roles are protected by Conditional Access policies enforcing phishing-resistant authentication"
        } else {
            $Status = 'Failed'
            $UnprotectedCount = $UnprotectedRoles.Count
            $ProtectedCount = $PrivilegedRoles.Count - $UnprotectedCount
            $Result = @"
Found $UnprotectedCount unprotected privileged roles out of $($PrivilegedRoles.Count) total ($ProtectedCount protected)
## Unprotected privileged roles:
$(($UnprotectedRoles | ForEach-Object { "- $($_.displayName)" }) -join "`n")
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    }
}

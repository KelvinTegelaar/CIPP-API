function Invoke-CippTestCyberIns_04 {
    <#
    .SYNOPSIS
    Cyber Insurance Q4 - MFA is required for cloud apps that hold sensitive data
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_04'; TestType = 'Identity'; Risk = 'High'; Name = 'MFA is required for cloud apps that hold sensitive data'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $MFAData = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'
        if (-not $MFAData) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No MFA data found for this tenant. Sync the report data first.'
            return
        }

        $Total = 0; $AllApps = 0; $SpecificApps = 0; $SecurityDefaults = 0
        foreach ($User in $MFAData) {
            if ($User.AccountEnabled -ne $true -or $User.UserType -ne 'Member') { continue }
            $Total++
            if ($User.CoveredByCA -eq 'Enforced - All Apps') { $AllApps++ }
            elseif ($User.CoveredBySD -eq $true) { $SecurityDefaults++ }
            elseif ($User.CoveredByCA -like 'Enforced*') { $SpecificApps++ }
        }

        if ($Total -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No enabled member users were found for this tenant.'
            return
        }

        $SsoApps = 0
        foreach ($App in (Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipals')) {
            if ($App.accountEnabled -eq $true -and $App.preferredSingleSignOnMode) { $SsoApps++ }
        }

        $Covered = $AllApps + $SecurityDefaults
        $Result = "Of $Total enabled member users, MFA covers every cloud app that signs in through Entra ID for **$Covered** ($AllApps by Conditional Access, $SecurityDefaults by Security Defaults). **$SpecificApps** are covered for specific apps only, and **$($Total - $Covered - $SpecificApps)** have no MFA enforced.`n`n$SsoApps enterprise apps use Entra ID single sign-on. Apps that do not sign in through Entra ID are not visible here and need an MSP attestation."

        $Status = if ($Covered -eq $Total) { 'Passed' } elseif (($Covered + $SpecificApps) -gt 0) { 'Investigate' } else { 'Failed' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_04: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}

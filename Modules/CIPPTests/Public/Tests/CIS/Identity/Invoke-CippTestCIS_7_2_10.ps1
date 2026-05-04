function Invoke-CippTestCIS_7_2_10 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.10) - Reauthentication with verification code SHALL be restricted
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_10' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Reauthentication with verification code is restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1
        $Required = $Cfg.EmailAttestationRequired
        $Days = [int]$Cfg.EmailAttestationReAuthDays

        if ($Required -eq $true -and $Days -gt 0 -and $Days -le 15) {
            $Status = 'Passed'
            $Result = "Email attestation re-auth is enforced every $Days days."
        } else {
            $Status = 'Failed'
            $Result = "Email attestation re-auth is not enforced (EmailAttestationRequired: $Required, EmailAttestationReAuthDays: $Days). CIS recommends 15 or less."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_10' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Reauthentication with verification code is restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_10' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Reauthentication with verification code is restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}

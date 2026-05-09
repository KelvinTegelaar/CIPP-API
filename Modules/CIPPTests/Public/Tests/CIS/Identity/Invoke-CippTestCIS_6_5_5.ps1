function Invoke-CippTestCIS_6_5_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.5.5) - Direct Send submissions SHALL be rejected
    #>
    param($Tenant)

    try {
        $Org = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $Org) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found.' -Risk 'Medium' -Name 'Direct Send submissions are rejected' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Email Authentication'
            return
        }

        $Cfg = $Org | Select-Object -First 1

        if ($Cfg.RejectDirectSend -eq $true) {
            $Status = 'Passed'
            $Result = 'Direct Send submissions are rejected (RejectDirectSend: true).'
        } else {
            $Status = 'Failed'
            $Result = "Direct Send submissions are accepted (RejectDirectSend: $($Cfg.RejectDirectSend)). Migrate scan-to-mail / app senders to authenticated SMTP relay or to a connector before enabling."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Direct Send submissions are rejected' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Direct Send submissions are rejected' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    }
}

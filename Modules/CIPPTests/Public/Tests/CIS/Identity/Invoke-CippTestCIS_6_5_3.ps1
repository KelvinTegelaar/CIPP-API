function Invoke-CippTestCIS_6_5_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.5.3) - Additional storage providers SHALL be restricted in Outlook on the web
    #>
    param($Tenant)

    try {
        $Owa = Get-CIPPTestData -TenantFilter $Tenant -Type 'OwaMailboxPolicy'

        if (-not $Owa) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'OwaMailboxPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Additional storage providers are restricted in Outlook on the web' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Default = $Owa | Where-Object { $_.Identity -eq 'OwaMailboxPolicy-Default' -or $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $Default) { $Default = $Owa | Select-Object -First 1 }

        if ($Default.AdditionalStorageProvidersAvailable -eq $false) {
            $Status = 'Passed'
            $Result = "Additional storage providers are disabled on '$($Default.Identity)'."
        } else {
            $Status = 'Failed'
            $Result = "Additional storage providers are enabled on '$($Default.Identity)' (AdditionalStorageProvidersAvailable: $($Default.AdditionalStorageProvidersAvailable))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Additional storage providers are restricted in Outlook on the web' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Additional storage providers are restricted in Outlook on the web' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}

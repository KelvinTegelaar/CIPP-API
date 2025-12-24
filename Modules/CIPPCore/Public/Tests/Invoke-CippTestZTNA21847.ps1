function Invoke-CippTestZTNA21847 {
    param($Tenant)

    $TestId = 'ZTNA21847'
    #Tested
    try {
        # Check if tenant has on-premises sync
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Organization'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Organization details not found' -Risk 'High' -Name 'Password protection for on-premises is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        $Org = $Settings[0]

        if ($Org.onPremisesSyncEnabled -ne $true) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Passed' -ResultMarkdown '✅ **Pass**: This tenant is not synchronized to an on-premises environment.' -Risk 'High' -Name 'Password protection for on-premises is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        # Note: Password protection settings require groupSettings API which is not cached
        # This test requires direct API access to check EnableBannedPasswordCheckOnPremises and BannedPasswordCheckOnPremisesMode
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Password protection settings require API access not available in cache. Manual verification required.' -Risk 'High' -Name 'Password protection for on-premises is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
        return

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Password protection for on-premises is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Password protection for on-premises is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}

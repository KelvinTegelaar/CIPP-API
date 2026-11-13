function Invoke-CippTestCIS_8_2_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (8.2.3) - External Teams users SHALL NOT be able to initiate conversations
    #>
    param($Tenant)

    try {
        $External = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsExternalAccessPolicy'
        $Federation = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTenantFederationConfiguration'

        if (-not $External -and -not $Federation) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (CsExternalAccessPolicy or CsTenantFederationConfiguration) not found.' -Risk 'High' -Name 'External Teams users cannot initiate conversations' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $E = @($External)[0]
        $F = @($Federation)[0]

        # CIS counts unmanaged communication being off entirely (8.2.2) as also blocking inbound contact.
        $CommunicationOff = $E.EnableTeamsConsumerAccess -eq $false -or $F.AllowTeamsConsumer -eq $false
        $InboundOff = $E.EnableTeamsConsumerInbound -eq $false -or $F.AllowTeamsConsumerInbound -eq $false
        $Detail = "`n`n- EnableTeamsConsumerInbound (policy): $($E.EnableTeamsConsumerInbound)`n- AllowTeamsConsumerInbound (tenant): $($F.AllowTeamsConsumerInbound)`n- EnableTeamsConsumerAccess (policy): $($E.EnableTeamsConsumerAccess)`n- AllowTeamsConsumer (tenant): $($F.AllowTeamsConsumer)"

        if ($InboundOff -or $CommunicationOff) {
            $Status = 'Passed'
            $Result = "Unmanaged Teams users cannot initiate conversations.$Detail"
        } else {
            $Status = 'Failed'
            $Result = "Unmanaged Teams users can initiate conversations with users in this organization.$Detail"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'External Teams users cannot initiate conversations' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'External Teams users cannot initiate conversations' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}

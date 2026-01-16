function Invoke-CippTestCISAMSEXO11 {
    <#
    .SYNOPSIS
    Tests MS.EXO.1.1 - Automatic forwarding to external domains SHALL be disabled

    .DESCRIPTION
    Checks if automatic forwarding to external domains is disabled across all remote domains

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $RemoteDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoRemoteDomain'

        if (-not $RemoteDomains) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoRemoteDomain cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Automatic forwarding to external domains SHALL be disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO11' -TestType 'Identity' -TenantFilter $Tenant
            return
        }

        $ForwardingEnabledDomains = $RemoteDomains | Where-Object { $_.AutoForwardEnabled -eq $true }

        if (($ForwardingEnabledDomains | Measure-Object).Count -eq 0) {
            $Result = '✅ **Pass**: Automatic forwarding to external domains is disabled for all remote domains.'
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($ForwardingEnabledDomains.Count) domain(s) have automatic forwarding enabled:`n`n"
            $Result += "| Domain Name | Auto Forward |`n"
            $Result += "| :---------- | :----------- |`n"
            foreach ($Domain in $ForwardingEnabledDomains) {
                $Result += "| $($Domain.DomainName) | $($Domain.AutoForwardEnabled) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO11' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Automatic forwarding to external domains SHALL be disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Automatic forwarding to external domains SHALL be disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO11' -TestType 'Identity' -TenantFilter $Tenant
    }
}

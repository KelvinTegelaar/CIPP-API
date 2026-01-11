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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoRemoteDomain cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO11' -TenantFilter $Tenant
            return
        }

        $ForwardingEnabledDomains = $RemoteDomains | Where-Object { $_.AutoForwardEnabled -eq $true }

        if (($ForwardingEnabledDomains | Measure-Object).Count -eq 0) {
            $Result = '✅ **Pass**: Automatic forwarding to external domains is disabled for all remote domains.'
            $Status = 'Pass'
        } else {
            $ResultTable = foreach ($Domain in $ForwardingEnabledDomains) {
                [PSCustomObject]@{
                    'Domain Name'  = $Domain.DomainName
                    'Auto Forward' = $Domain.AutoForwardEnabled
                }
            }

            $Result = "❌ **Fail**: $($ForwardingEnabledDomains.Count) domain(s) have automatic forwarding enabled:`n`n"
            $Result += ($ResultTable | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO11' -Status $Status -ResultMarkdown $Result -Risk 'High' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO11' -TenantFilter $Tenant
    }
}
function Invoke-CippTestCISAMSEXO11 {
    <#
    .SYNOPSIS
    MS.EXO.1.1 - Automatic forwarding to external domains SHALL be disabled
    
    .DESCRIPTION
    Tests if automatic forwarding to external domains is disabled in Exchange Online
    
    .LINK
    https://github.com/cisagov/ScubaGear
    #>
    param($Tenant)
    
    try {
        $RemoteDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoRemoteDomain'
        
        if (-not $RemoteDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO11' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoRemoteDomain cache not found. Please ensure cache data is available.' -Risk 'High' -Name 'Auto-forwarding to external domains is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
            return
        }
        
        $ForwardingEnabledDomains = $RemoteDomains | Where-Object { $_.AutoForwardEnabled -eq $true }
        
        if ($ForwardingEnabledDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = "✅ Well done. Your tenant has automatic forwarding disabled for all remote domains.`n`n"
            $Result += "| Domain Name | Auto Forward Enabled |`n"
            $Result += "| --- | --- |`n"
            foreach ($domain in $RemoteDomains) {
                $Result += "| $($domain.DomainName) | ❌ Disabled |`n"
            }
        } else {
            $Status = 'Failed'
            $Result = "❌ Your tenant has automatic forwarding enabled for some remote domains.`n`n"
            $Result += "| Domain Name | Auto Forward Enabled | Result |`n"
            $Result += "| --- | --- | --- |`n"
            foreach ($domain in $RemoteDomains) {
                $enabled = if ($domain.AutoForwardEnabled) { '✅ Enabled' } else { '❌ Disabled' }
                $testResult = if ($domain.AutoForwardEnabled) { '❌ Fail' } else { '✅ Pass' }
                $Result += "| $($domain.DomainName) | $enabled | $testResult |`n"
            }
        }
        
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO11' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Auto-forwarding to external domains is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run CISA test CISAMSEXO11: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO11' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Auto-forwarding to external domains is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
    }
}

function Invoke-CippTestCISAMSEXO31 {
    <#
    .SYNOPSIS
    Tests MS.EXO.3.1 - DKIM SHOULD be enabled for all domains

    .DESCRIPTION
    Checks if DKIM (DomainKeys Identified Mail) signing is enabled for all accepted domains

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $DkimConfigs = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoDkimSigningConfig'
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $DkimConfigs -or -not $AcceptedDomains) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'Required cache (ExoDkimSigningConfig or ExoAcceptedDomains) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO31' -TenantFilter $Tenant
            return
        }

        # Filter to non-internal accepted domains
        $SendingDomains = $AcceptedDomains | Where-Object { -not $_.SendingFromDomainDisabled }

        if (($SendingDomains | Measure-Object).Count -eq 0) {
            Add-CippTestResult -Status 'Pass' -ResultMarkdown '✅ **Pass**: No sending domains found to check DKIM configuration.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO31' -TenantFilter $Tenant
            return
        }

        $FailedDomains = [System.Collections.Generic.List[object]]::new()

        foreach ($Domain in $SendingDomains) {
            $DkimConfig = $DkimConfigs | Where-Object { $_.Domain -eq $Domain.DomainName }

            if (-not $DkimConfig -or -not $DkimConfig.Enabled) {
                $FailedDomains.Add([PSCustomObject]@{
                    'Domain' = $Domain.DomainName
                    'DKIM Enabled' = if ($DkimConfig) { $DkimConfig.Enabled } else { 'Not Configured' }
                    'Status' = if (-not $DkimConfig) { 'No DKIM config found' } else { 'DKIM disabled' }
                })
            }
        }

        if ($FailedDomains.Count -eq 0) {
            $Result = "✅ **Pass**: DKIM is enabled for all $($SendingDomains.Count) sending domain(s)."
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: $($FailedDomains.Count) of $($SendingDomains.Count) domain(s) do not have DKIM properly enabled:`n`n"
            $Result += ($FailedDomains | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO31' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO31' -TenantFilter $Tenant
    }
}

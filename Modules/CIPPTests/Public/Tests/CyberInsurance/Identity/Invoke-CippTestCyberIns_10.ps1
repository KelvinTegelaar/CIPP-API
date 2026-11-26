function Invoke-CippTestCyberIns_10 {
    <#
    .SYNOPSIS
    Cyber Insurance Q10 - Email security and filtering is in place
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_10'; TestType = 'Identity'; Risk = 'High'; Name = 'Email security and filtering is in place'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $AntiPhish = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies').Where({ $_.Enabled -eq $true }).Count
        $Malware = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies').Where({ $_ }).Count
        $Domains = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'DomainAnalyser').Where({ $_.Domain -notlike '*.onmicrosoft.com' })

        if ($AntiPhish -eq 0 -and $Malware -eq 0 -and $Domains.Count -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No email protection data found for this tenant. Sync the report data first.'
            return
        }

        $Licensed = Test-CIPPStandardLicense -StandardName 'CyberIns_10' -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog
        $SafeLinks = 0; $SafeAttachments = 0
        if ($Licensed) {
            $SafeLinks = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies').Where({ $_.EnableSafeLinksForEmail -eq $true }).Count
            $SafeAttachments = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeAttachmentPolicies').Where({ $_.Enable -eq $true }).Count
        }
        $Connectors = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoInboundConnector').Where({ $_.Enabled -eq $true }).Count

        $ThirdParty = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Domain in $Domains) {
            $Provider = [string]$Domain.MailProvider
            if ($Provider -and $Provider -notin @('Unknown', 'Null') -and $Provider -notlike '*Microsoft*') { $null = $ThirdParty.Add($Provider) }
        }

        $Result = [System.Text.StringBuilder]::new()
        if ($Licensed) {
            $null = $Result.Append("Defender for Office 365 is licensed: **$SafeLinks** Safe Links policies cover email and **$SafeAttachments** Safe Attachments policies are enabled.`n`n")
        } else {
            $null = $Result.Append("Defender for Office 365: not licensed.`n`n")
        }
        $null = $Result.Append("Exchange Online Protection: **$AntiPhish** anti-phishing policies enabled and **$Malware** malware filter policies.`n`n")
        if ($ThirdParty.Count -gt 0) {
            $null = $Result.Append("Mail for at least one domain is delivered through a third-party gateway: $(@($ThirdParty) -join ', '). $Connectors inbound connectors are enabled.`n")
        } else {
            $null = $Result.Append("No third-party mail gateway was found on the tenant's $($Domains.Count) custom domains.`n")
        }

        $Status = if (($SafeLinks -gt 0 -and $SafeAttachments -gt 0) -or $ThirdParty.Count -gt 0) { 'Passed' } elseif ($AntiPhish -gt 0 -or $Malware -gt 0) { 'Investigate' } else { 'Failed' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_10: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}

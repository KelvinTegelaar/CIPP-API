function Invoke-CippTestCyberIns_15 {
    <#
    .SYNOPSIS
    Cyber Insurance Q15 - Sensitive data is encrypted in transit
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_15'; TestType = 'Identity'; Risk = 'Medium'; Name = 'Sensitive data is encrypted in transit'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $TransportConfig = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoTransportConfig')[0]
        $Domains = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'DomainAnalyser').Where({ $_.Domain -notlike '*.onmicrosoft.com' -and $_.MTASTS -ne 'Not applicable' })

        if (-not $TransportConfig -and $Domains.Count -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No mail transport data found for this tenant. Sync the report data first.'
            return
        }

        $SmtpAuthDisabled = $TransportConfig.SmtpClientAuthenticationDisabled -eq $true
        $Enforced = $Domains.Where({ $_.MTASTS -eq 'Enforced' }).Count
        $TlsConnectors = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOutboundConnector').Where({ $_.Enabled -eq $true -and $_.TlsSettings }).Count
        $EncryptionRules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoTransportRules').Where({ $_.State -eq 'Enabled' -and ($_.ApplyOME -eq $true -or $_.ApplyRightsProtectionTemplate) }).Count

        $Result = "SMTP AUTH is disabled for the organisation: **$(if ($SmtpAuthDisabled) { 'Yes' } else { 'No' })**.`n`nMTA-STS is enforced on **$Enforced of $($Domains.Count)** custom mail domains.`n`n**$TlsConnectors** outbound connectors require TLS, and **$EncryptionRules** mail flow rules apply message encryption."

        $Status = if ($SmtpAuthDisabled -and $Domains.Count -gt 0 -and $Enforced -eq $Domains.Count) { 'Passed' } else { 'Investigate' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_15: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}

function Invoke-CIPPStandardTeamsZAP {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsZAP
    .SYNOPSIS
        (Label) Ensure Zero-hour auto purge for Microsoft Teams is on
    .DESCRIPTION
        (Helptext) Ensures Zero-hour auto purge (ZAP) is enabled for Microsoft Teams, automatically removing malicious messages after delivery.
        (DocsDescription) Zero-hour auto purge (ZAP) for Microsoft Teams retroactively detects and neutralises malicious messages that have already been delivered in Teams chats. Enabling ZAP ensures that phishing, malware, and high confidence phishing messages are automatically purged even after initial delivery, aligning with CIS M365 6.0.1 benchmark control 2.4.4.
    .NOTES
        CAT
            Defender Standards
        TAG
            "CIS M365 6.0.1 (2.4.4)"
        EXECUTIVETEXT
            Enables Zero-hour auto purge for Microsoft Teams to automatically detect and remove malicious messages after delivery. This provides an additional layer of protection against phishing and malware that may bypass initial scanning, ensuring threats are neutralised even after they reach users.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2026-05-06
        POWERSHELLEQUIVALENT
            Set-TeamsProtectionPolicy -Identity 'Teams Protection Policy' -ZapEnabled $true
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsZAP' -TenantFilter $Tenant -Preset Exchange
    if ($TestResult -eq $false) { return $true }

    try {
        $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TeamsProtectionPolicy' -cmdParams @{ Identity = 'Teams Protection Policy' }).ZapEnabled
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "TeamsZAP: Failed to get Teams Protection Policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $StateIsCorrect = $CurrentState -eq $true

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams ZAP is already enabled.' -sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TeamsProtectionPolicy' -cmdParams @{
                    Identity   = 'Teams Protection Policy'
                    ZapEnabled = $true
                }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Successfully enabled Teams ZAP.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable Teams ZAP. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams ZAP is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Teams Zero-hour auto purge (ZAP) is not enabled.' -object @{ ZapEnabled = $CurrentState } -tenant $Tenant -standardName 'TeamsZAP' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            ZapEnabled = $CurrentState
        }
        $ExpectedValue = [PSCustomObject]@{
            ZapEnabled = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsZAP' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'TeamsZAP' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}

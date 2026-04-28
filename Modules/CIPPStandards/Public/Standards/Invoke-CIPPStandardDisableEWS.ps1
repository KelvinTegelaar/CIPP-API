function Invoke-CIPPStandardDisableEWS {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableEWS
    .SYNOPSIS
        (Label) Disable Exchange Web Services
    .DESCRIPTION
        (Helptext) Disables Exchange Web Services (EWS) organization-wide. This reduces the attack surface by blocking legacy API access to mailbox data. Warning: This may break Office web add-ins on builds older than 16.0.19127.
        (DocsDescription) Disables Exchange Web Services (EWS) at the organization level to reduce attack surface. EWS provides cross-platform API access to sensitive Exchange Online data such as emails, meetings, and contacts. If compromised, attackers can access confidential data, send phishing emails, or spoof identities. Disabling EWS also reduces legacy app usage and minimizes exploitable endpoints. Note that this may break first-party features including web add-ins for Word, Excel, PowerPoint, and Outlook on builds older than 16.0.19127.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Disables Exchange Web Services (EWS) across the organization to reduce attack surface and prevent legacy API access to sensitive mailbox data. This aligns with Microsoft's Baseline Security Mode recommendation to minimize exploitable endpoints while requiring updates to applications that depend on EWS.
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2026-04-28
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -EwsEnabled $false
        RECOMMENDEDBY
            "CIPP"
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
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableEWS' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE')

    if ($TestResult -eq $false) {
        return $true
    }

    try {
        $EwsStatus = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').EwsEnabled
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableEWS state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($EwsStatus -eq $false) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Exchange Web Services is already disabled.' -Sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ EwsEnabled = $false } -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully disabled Exchange Web Services.' -Sev Info
                $EwsStatus = $false
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to disable Exchange Web Services. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($EwsStatus -eq $false) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Exchange Web Services is disabled.' -Sev Info
        } else {
            Write-StandardsAlert -message 'Exchange Web Services is enabled.' -object $EwsStatus -tenant $Tenant -standardName 'DisableEWS' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Exchange Web Services is enabled.' -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $StateIsCorrect = $EwsStatus -eq $false

        $CurrentValue = [PSCustomObject]@{
            DisableEWS = $StateIsCorrect
        }
        $ExpectedValue = [PSCustomObject]@{
            DisableEWS = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableEWS' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableEWS' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}

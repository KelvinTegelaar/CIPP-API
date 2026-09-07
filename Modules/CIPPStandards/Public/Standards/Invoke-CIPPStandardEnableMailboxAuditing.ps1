function Invoke-CIPPStandardEnableMailboxAuditing {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableMailboxAuditing
    .SYNOPSIS
        (Label) Enable Mailbox auditing
    .DESCRIPTION
        (Helptext) Enables Mailbox auditing for all mailboxes and on tenant level. Disables audit bypass on all mailboxes. Unified Audit Log needs to be enabled for this standard to function.
        (DocsDescription) Enables mailbox auditing on tenant level and for all mailboxes. Disables audit bypass on all mailboxes. By default Microsoft does not enable mailbox auditing for Resource Mailboxes, Public Folder Mailboxes and DiscoverySearch Mailboxes. Unified Audit Log needs to be enabled for this standard to function.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS M365 5.0 (6.1.1)"
            "CIS M365 5.0 (6.1.2)"
            "CIS M365 5.0 (6.1.3)"
            "exo_mailboxaudit"
            "Essential 8 (1509)"
            "Essential 8 (1683)"
            "NIST CSF 2.0 (DE.CM-09)"
            "CISAMSEXO131"
        EXECUTIVETEXT
            Enables comprehensive logging of all email access and modifications across all employee mailboxes, providing detailed audit trails for security investigations and compliance requirements. This helps detect unauthorized access, data breaches, and supports regulatory compliance efforts.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-01-08
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -AuditDisabled \$false
        RECOMMENDEDBY
            "CIS"
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
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EnableMailboxAuditing' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $AuditState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').AuditDisabled
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EnableMailboxAuditing state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($AuditState) {
            # Enable tenant level mailbox audit
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{AuditDisabled = $false } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit enabled' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable tenant level mailbox audit. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit already enabled' -sev Info
        }

        # Per-mailbox AuditEnabled is intentionally not set here. With mailbox auditing on by default
        # (AuditDisabled = $false, set above) Microsoft applies the default per-sign-in-type audit
        # action sets and Get-Mailbox reports AuditEnabled = True on supported mailboxes, so enabling
        # each mailbox individually is redundant.
        # https://learn.microsoft.com/en-us/purview/audit-mailboxes

        # Disable audit bypass for any mailbox that has it enabled, so no user is excluded from
        # auditing. The bypass flag is not a Get-Mailbox property - it lives on the association.
        try {
            $BypassMailboxes = @(New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxAuditBypassAssociation' -useSystemMailbox $true | Where-Object { $_.AuditBypassEnabled -eq $true })
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve mailbox audit bypass associations. Error: $ErrorMessage" -sev Error
            $BypassMailboxes = @()
        }

        if ($BypassMailboxes.Count -gt 0) {
            $Request = foreach ($Mailbox in $BypassMailboxes) {
                @{
                    CmdletInput = @{
                        CmdletName = 'Set-MailboxAuditBypassAssociation'
                        Parameters = @{Identity = $Mailbox.Guid; AuditBypassEnabled = $false }
                    }
                }
            }

            $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
            foreach ($Result in $BatchResults) {
                if ($Result.error) {
                    $ErrorMessage = Get-NormalizedError -Message $Result.error
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable mailbox audit bypass for $($Result.target). Error: $ErrorMessage" -sev Error
                }
            }
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Disabled mailbox audit bypass for $($BypassMailboxes.Count) mailbox(es)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No mailboxes have audit bypass enabled' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($AuditState) {
            Write-StandardsAlert -message 'Tenant level mailbox audit is not enabled' -object $AuditState -tenant $Tenant -standardName 'EnableMailboxAuditing' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit is not enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit is enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $AuditState = -not $AuditState

        $CurrentValue = [PSCustomObject]@{
            EnableMailboxAuditing = $AuditState
        }
        $ExpectedValue = [PSCustomObject]@{
            EnableMailboxAuditing = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.EnableMailboxAuditing' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'MailboxAuditingEnabled' -FieldValue $AuditState -StoreAs bool -Tenant $Tenant
    }

}

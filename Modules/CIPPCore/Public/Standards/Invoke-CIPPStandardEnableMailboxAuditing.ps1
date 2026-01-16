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
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EnableMailboxAuditing' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
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
                $LogMessage = 'Tenant level mailbox audit enabled. '
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable tenant level mailbox audit. Error: $ErrorMessage" -sev Error
            }
        } else {
            $LogMessage = 'Tenant level mailbox audit already enabled. '
        }

        # Commented out because MS recommends NOT doing this anymore. From docs: https://learn.microsoft.com/en-us/purview/audit-mailboxes#verify-mailbox-auditing-on-by-default-is-turned-on
        # When you turn on mailbox auditing on by default for the organization, the AuditEnabled property for affected mailboxes doesn't change from False to True. In other words, mailbox auditing on by default ignores the AuditEnabled property on mailboxes.
        # Auditing is automatically turned on when you create a new mailbox. You don't need to manually enable mailbox auditing for new users.
        # You don't need to manage the mailbox actions that are audited. A predefined set of mailbox actions are audited by default for each sign-in type (Admin, Delegate, and Owner).
        # When Microsoft releases a new mailbox action, the action might be added automatically to the list of mailbox actions that are audited by default (subject to the user having the appropriate license). This result means you don't need to add new actions on mailboxes as they're released.
        # You have a consistent mailbox auditing policy across your organization because you're auditing the same actions for all mailboxes.
        #$Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{filter = "auditenabled -eq 'False'" } -useSystemMailbox $true -Select 'AuditEnabled,UserPrincipalName'
        #$Request = $mailboxes | ForEach-Object {
        #    @{
        #       CmdletInput = @{
        #          CmdletName = 'Set-Mailbox'
        #         Parameters = @{Identity = $_.UserPrincipalName; AuditEnabled = $true }
        #    }
        #}
        #}

        #$BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
        #$BatchResults | ForEach-Object {
        #    if ($_.error) {
        #        $ErrorMessage = Get-NormalizedError -Message $_.error
        #        Write-Host "Failed to enable user level mailbox audit for $($_.target). Error: $ErrorMessage"
        #        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable user level mailbox audit for $($_.target). Error: $ErrorMessage" -sev Error
        # }
        #}

        # Disable audit bypass for all mailboxes that have it enabled

        $BypassMailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxAuditBypassAssociation' -select 'GUID, AuditBypassEnabled, Name' -useSystemMailbox $true | Where-Object { $_.AuditBypassEnabled -eq $true }
        $Request = $BypassMailboxes | ForEach-Object {
            @{
                CmdletInput = @{
                    CmdletName = 'Set-MailboxAuditBypassAssociation'
                    Parameters = @{Identity = $_.Guid; AuditBypassEnabled = $false }
                }
            }
        }

        $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
        $BatchResults | ForEach-Object {
            if ($_.error) {
                $ErrorMessage = Get-NormalizedError -Message $_.error
                Write-Host "Failed to disable mailbox audit bypass for $($_.target). Error: $ErrorMessage"
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable mailbox audit bypass for $($_.target). Error: $ErrorMessage" -sev Error
            }
        }

        $LogMessage = if ($Mailboxes.Count -eq 0 -and $BypassMailboxes.Count -eq 0) {
            # Make log message smaller if both are already in the desired state
            'User level mailbox audit already enabled and mailbox audit bypass already disabled for all mailboxes'
        } else {
            if ($Mailboxes.Count -eq 0) {
                'User level mailbox audit already enabled for all mailboxes. '
            }
            if ($BypassMailboxes.Count -eq 0) {
                'Mailbox audit bypass already disabled for all mailboxes'
            }
        }

        Write-LogMessage -API 'Standards' -tenant $Tenant -message $LogMessage -sev Info
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

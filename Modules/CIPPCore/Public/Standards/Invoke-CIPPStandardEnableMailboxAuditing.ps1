function Invoke-CIPPStandardEnableMailboxAuditing {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $AuditState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').AuditDisabled

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

        # Check for mailbox audit on all mailboxes. Enable for all that it's not enabled for
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{filter = "auditenabled -eq 'False'" } -useSystemMailbox $true -Select 'AuditEnabled,UserPrincipalName'
        $Request = $mailboxes | ForEach-Object {
            @{
                CmdletInput = @{
                    CmdletName = 'Set-Mailbox'
                    Parameters = @{Identity = $_.UserPrincipalName; AuditEnabled = $true }
                }
            }
        }

        $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
        $BatchResults | ForEach-Object {
            if ($_.error) {
                $ErrorMessage = Get-NormalizedError -Message $_.error
                Write-Host "Failed to enable user level mailbox audit for $($_.target). Error: $ErrorMessage"
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable user level mailbox audit for $($_.target). Error: $ErrorMessage" -sev Error
            }
        }

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
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit is not enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit is enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $AuditState = -not $AuditState
        Add-CIPPBPAField -FieldName 'MailboxAuditingEnabled' -FieldValue $AuditState -StoreAs bool -Tenant $Tenant
    }

}

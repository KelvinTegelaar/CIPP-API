function Invoke-CIPPStandardEnableOnlineArchiving {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $MailboxPlans = @( 'ExchangeOnline', 'ExchangeOnlineEnterprise' )
    $MailboxesNoArchive = $MailboxPlans | ForEach-Object { 
        New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdparams @{ MailboxPlan = $_; Filter = 'ArchiveGuid -Eq "00000000-0000-0000-0000-000000000000" -AND RecipientTypeDetails -Eq "UserMailbox"' } 
        Write-Host "Getting mailboxes without Online Archiving for plan $_"
    }

    If ($Settings.remediate) {

        if ($null -eq $MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Online Archiving already enabled for all accounts' -sev Info
        } else {
            try {
                $SuccessCounter = 0
                $MailboxesNoArchive | ForEach-Object {
                    try {
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Enable-Mailbox' -cmdparams @{ Identity = $_.UserPrincipalName; Archive = $true } | Out-Null
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Enabled Online Archiving for $($_.UserPrincipalName)" -sev Info
                        $SuccessCounter++
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to Enable Online Archiving for $($_.UserPrincipalName). Error: $($_.exception.message)" -sev Error
                    }
                }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Enabled Online Archiving for $SuccessCounter accounts" -sev Info
        
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to Enable Online Archiving for all accounts. Error: $($_.exception.message)" -sev Error
            }
        }

    }

    if ($Settings.alert) {

        if ($MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.Count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have Online Archiving enabled' -sev Info
        }
    }

    if ($Settings.report) {
        $filtered = $MailboxesNoArchive | Select-Object -Property UserPrincipalName, ArchiveGuid
        Add-CIPPBPAField -FieldName 'EnableOnlineArchiving' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }
}

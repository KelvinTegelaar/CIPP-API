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

    If ($Settings.remediate -eq $true) {

        if ($null -eq $MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Online Archiving already enabled for all accounts' -sev Info
        } else {
            try {
                $Request = $MailboxesNoArchive | ForEach-Object {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Enable-Mailbox'
                            Parameters = @{ Identity = $_.UserPrincipalName; Archive = $true }
                        }
                    }
                }

                $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-NormalizedError -Message $_.error
                        Write-Host "Failed to Enable Online Archiving for $($_.Target). Error: $ErrorMessage"
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Enable Online Archiving for $($_.Target). Error: $ErrorMessage" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to Enable Online Archiving for all accounts. Error: $ErrorMessage" -sev Error
            }
        }

    }

    if ($Settings.alert -eq $true) {

        if ($MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.Count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have Online Archiving enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $filtered = $MailboxesNoArchive | Select-Object -Property UserPrincipalName, ArchiveGuid
        Add-CIPPBPAField -FieldName 'EnableOnlineArchiving' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }
}

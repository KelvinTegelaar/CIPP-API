function Invoke-CIPPStandardSafeSendersDisable {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    If ($Settings.remediate -eq $true) {
        try {
            $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -select 'UserPrincipalName'
            $Request = $Mailboxes | ForEach-Object {
                @{
                    CmdletInput = @{
                        CmdletName = 'Set-MailboxJunkEmailConfiguration'
                        Parameters = @{
                            Identity                    = $_.UserPrincipalName
                            TrustedRecipientsAndDomains = $null
                        }
                    }
                }
            }

            $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
            $BatchResults | ForEach-Object {
                if ($_.error) {
                    $ErrorMessage = Get-NormalizedError -Message $_.error
                    Write-Host "Failed to Disable SafeSenders for $($_.target). Error: $ErrorMessage"
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Disable SafeSenders for $($_.target). Error: $ErrorMessage" -sev Error
                }
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Safe Senders disabled' -sev Info
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SafeSenders. Error: $ErrorMessage" -sev Error
        }
    }

}

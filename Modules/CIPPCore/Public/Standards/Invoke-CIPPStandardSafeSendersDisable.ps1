function Invoke-CIPPStandardSafeSendersDisable {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SafeSendersDisable
    .SYNOPSIS
        (Label) Remove Safe Senders to prevent SPF bypass
    .DESCRIPTION
        (Helptext) Loops through all users and removes the Safe Senders list. This is to prevent SPF bypass attacks, as the Safe Senders list is not checked by SPF.
        (DocsDescription) Loops through all users and removes the Safe Senders list. This is to prevent SPF bypass attacks, as the Safe Senders list is not checked by SPF.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Removes user-defined safe sender lists to prevent security bypasses where malicious emails could avoid spam filtering. This ensures all emails go through proper security screening, even if users have previously marked senders as 'safe', improving overall email security.
        ADDEDCOMPONENT
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2023-10-26
        POWERSHELLEQUIVALENT
            Set-MailboxJunkEmailConfiguration
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SafeSendersDisable' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    if ($Settings.remediate -eq $true) {
        try {
            $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -select 'UserPrincipalName'
            $Request = foreach ($Mailbox in $Mailboxes) {
                @{
                    CmdletInput = @{
                        CmdletName = 'Set-MailboxJunkEmailConfiguration'
                        Parameters = @{
                            Identity                    = $Mailbox.UserPrincipalName
                            TrustedRecipientsAndDomains = $null
                        }
                    }
                }
            }

            $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
            foreach ($Result in $BatchResults) {
                if ($Result.error) {
                    $ErrorMessage = Get-NormalizedError -Message $Result.error
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Disable SafeSenders for $($Result.target). Error: $ErrorMessage" -sev Error
                }
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Safe Senders disabled' -sev Info
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SafeSenders. Error: $ErrorMessage" -sev Error
        }
    }

    if ($Settings.report -eq $true) {
        #This script always returns true, as it only disables the Safe Senders list
        $CurrentValue = @{
            SafeSendersDisabled = $true
        }
        $ExpectedValue = @{
            SafeSendersDisabled = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SafeSendersDisable' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }

}

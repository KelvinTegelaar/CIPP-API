function Invoke-CIPPStandardDisableResourceMailbox {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableResourceMailbox
    .SYNOPSIS
        (Label) Disable Unlicensed Resource Mailbox Entra accounts
    .DESCRIPTION
        (Helptext) Blocks login for all accounts that are marked as a resource mailbox and does not have a license assigned. Accounts that are synced from on-premises AD are excluded, as account state is managed in the on-premises AD.
        (DocsDescription) Resource mailboxes can be directly logged into if the password is reset, this presents a security risk as do all shared login credentials. Microsoft's recommendation is to disable the user account for resource mailboxes. Accounts that are synced from on-premises AD are excluded, as account state is managed in the on-premises AD.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "NIST CSF 2.0 (PR.AA-01)"
        EXECUTIVETEXT
            Prevents direct login to resource mailbox accounts (like conference rooms or equipment), ensuring they can only be managed through proper administrative channels. This security measure eliminates potential unauthorized access to resource scheduling systems while maintaining proper booking functionality.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-06-01
        POWERSHELLEQUIVALENT
            Get-Mailbox & Update-MgUser
        RECOMMENDEDBY
            "Microsoft"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableResourceMailbox' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Get all users that are able to be
    try {
        $AllUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'
        $UserList = $AllUsers | Where-Object {
            $_.accountEnabled -eq $true -and
            $_.onPremisesSyncEnabled -ne $true -and
            ($null -eq $_.assignedLicenses -or $_.assignedLicenses.Count -eq 0) -and
            $_.userType -eq 'Member'
        }
        $ResourceMailboxList = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ Filter = "RecipientTypeDetails -eq 'RoomMailbox' -or RecipientTypeDetails -eq 'EquipmentMailbox'" } -Select 'UserPrincipalName,DisplayName,RecipientTypeDetails,ExternalDirectoryObjectId' |
            Where-Object { $_.ExternalDirectoryObjectId -in $UserList.id }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableResourceMailbox state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        $UpdateDB = $false
        if ($ResourceMailboxList.Count -gt 0) {
            $int = 0
            $BulkRequests = foreach ($Mailbox in $ResourceMailboxList) {
                @{
                    id        = $int++
                    method    = 'PATCH'
                    url       = "users/$($Mailbox.ExternalDirectoryObjectId)"
                    body      = @{ accountEnabled = $false }
                    'headers' = @{
                        'Content-Type' = 'application/json'
                    }
                }
            }

            try {
                $BulkResults = New-GraphBulkRequest -tenantid $Tenant -Requests @($BulkRequests)

                for ($i = 0; $i -lt $BulkResults.Count; $i++) {
                    $result = $BulkResults[$i]
                    $Mailbox = $ResourceMailboxList[$i]

                    if ($result.status -eq 200 -or $result.status -eq 204) {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Entra account for $($Mailbox.RecipientTypeDetails), $($Mailbox.DisplayName), $($Mailbox.UserPrincipalName) disabled." -sev Info
                        $UpdateDB = $true
                    } else {
                        $errorMsg = if ($result.body.error.message) { $result.body.error.message } else { "Unknown error (Status: $($result.status))" }
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable Entra account for $($Mailbox.RecipientTypeDetails), $($Mailbox.DisplayName), $($Mailbox.UserPrincipalName): $errorMsg" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to process bulk disable resource mailboxes request: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }

            # Refresh user cache after remediation only if changes were made
            if ($UpdateDB) {
                try {
                    Set-CIPPDBCacheUsers -TenantFilter $Tenant
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to refresh user cache after remediation: $($_.Exception.Message)" -sev Warning
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All Entra accounts for resource mailboxes are already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($ResourceMailboxList) {
            Write-StandardsAlert -message "Resource mailboxes with enabled accounts: $($ResourceMailboxList.Count)" -object $ResourceMailboxList -tenant $Tenant -standardName 'DisableResourceMailbox' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Resource mailboxes with enabled accounts: $($ResourceMailboxList.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All Entra accounts for resource mailboxes are disabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            ResourceMailboxesToDisable = @($ResourceMailboxList)
        }
        $ExpectedValue = [PSCustomObject]@{
            ResourceMailboxesToDisable = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableResourceMailbox' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableResourceMailbox' -FieldValue $ResourceMailboxList -StoreAs json -Tenant $Tenant
    }
}

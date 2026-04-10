function Invoke-CIPPStandardEnableExchangeCloudManagement {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableExchangeCloudManagement
    .SYNOPSIS
        (Label) Configure Exchange Cloud Management for Remote Mailboxes
    .DESCRIPTION
        (Helptext) Configures cloud-based management of Exchange attributes for directory-synced users with remote mailboxes in Exchange Online. This allows you to enable or disable management of Exchange attributes directly in the cloud without requiring an on-premises Exchange server.
        (DocsDescription) Configures the IsExchangeCloudManaged property for mailboxes, allowing Exchange attributes (aliases, mailbox flags, custom attributes, etc.) to be managed directly in Exchange Online or revert back to on-premises management. This feature helps organizations retire their last on-premises Exchange server in hybrid deployments while maintaining the ability to manage recipient attributes. Identity attributes (names, UPN) remain managed on-premises via Active Directory.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "lowimpact"
            "ExchangeOnline"
            "HybridDeployment"
        EXECUTIVETEXT
            Configures cloud-based management of Exchange mailbox attributes for hybrid organizations. When enabled, eliminates the dependency on on-premises Exchange servers for attribute management. This modernizes email administration, reduces infrastructure complexity, and allows direct management of mailbox properties through cloud portals and PowerShell. When disabled, returns management to on-premises Exchange servers.
        ADDEDCOMPONENT
            {"type": "select", "multiple": false, "name": "standards.EnableExchangeCloudManagement.state", "label": "Cloud Management State", "options": [{"label": "Enabled", "value": "enabled"}, {"label": "Disabled", "value": "disabled"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-11-14
        POWERSHELLEQUIVALENT
            Set-Mailbox -Identity user@domain.com -IsExchangeCloudManaged \$true or \$false
        RECOMMENDEDBY
            "Microsoft"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'EnableExchangeCloudManagement' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    }

    $DesiredState = [System.Convert]::ToBoolean($Settings.state)
    $StateText = if ($DesiredState) { 'Cloud' } else { 'On-Premises' }

    try {
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -Select 'UserPrincipalName,IsExchangeCloudManaged,RecipientTypeDetails,ExternalDirectoryObjectId,IsDirSynced' |
            Where-Object { $_.IsDirSynced -eq $true }

        $StateIsCorrect = ($Mailboxes | Where-Object { $_.IsExchangeCloudManaged -ne $DesiredState }).Count -eq 0
        $MailboxesToUpdate = $Mailboxes | Where-Object { $_.IsExchangeCloudManaged -ne $DesiredState }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve mailbox cloud management status. Error: $ErrorMessage" -sev Error -LogData $ErrorMessage
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All remote mailboxes are already managed in $StateText" -sev Info
        } else {
            try {
                $Request = $MailboxesToUpdate | ForEach-Object {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{
                                Identity               = $_.ExternalDirectoryObjectId
                                IsExchangeCloudManaged = $DesiredState
                            }
                        }
                    }
                }

                $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
                $SuccessCount = 0
                $FailCount = 0

                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-NormalizedError -Message $_.error
                        Write-Host "Failed to set mailbox management to $StateText for $($_.Target). Error: $ErrorMessage"
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set mailbox management to $StateText for $($_.Target). Error: $ErrorMessage" -sev Error
                        $FailCount++
                    } else {
                        $SuccessCount++
                    }
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set $SuccessCount mailbox(es) to $StateText management. Failed: $FailCount" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set mailbox management to $StateText. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $false) {
            $Object = $MailboxesToUpdate | Select-Object -Property UserPrincipalName, IsExchangeCloudManaged, RecipientTypeDetails, ExternalDirectoryObjectId
            Write-StandardsAlert -message "Remote mailboxes not managed in $StateText : $($MailboxesToUpdate.Count)" -object $Object -tenant $Tenant -standardName 'EnableExchangeCloudManagement' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Remote mailboxes not managed in $StateText : $($MailboxesToUpdate.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All remote mailboxes are managed in $StateText" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $filtered = $MailboxesToUpdate | Select-Object -Property UserPrincipalName, IsExchangeCloudManaged, RecipientTypeDetails, ExternalDirectoryObjectId
        $stateReport = if ($StateIsCorrect -eq $true) { $true } else { $filtered }
        Set-CIPPStandardsCompareField -FieldName 'standards.EnableExchangeCloudManagement' -FieldValue $stateReport -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EnableExchangeCloudManagement' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }
}

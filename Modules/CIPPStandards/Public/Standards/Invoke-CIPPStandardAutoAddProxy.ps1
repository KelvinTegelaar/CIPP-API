function Invoke-CIPPStandardAutoAddProxy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AutoAddProxy
    .SYNOPSIS
        (Label) Automatically deploy proxy addresses
    .DESCRIPTION
        (Helptext) Automatically adds all available domains as a proxy address.
        (DocsDescription) Automatically finds all available domain names in the tenant, and tries to add proxy addresses based on the user's UPN to each of these.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Automatically creates email addresses for employees across all company domains, ensuring they can receive emails sent to any of the organization's domain names. This improves email delivery reliability and maintains consistent communication channels across different business units or brands.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-02-07
        POWERSHELLEQUIVALENT
            Set-Mailbox -EmailAddresses @{add=\$EmailAddress}
        RECOMMENDEDBY
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param(
        $Tenant,
        $Settings,
        $QueueItem
    )

    $TestResult = Test-CIPPStandardLicense -StandardName 'AutoArchive' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE')
    if ($TestResult -eq $false) {
        return $true
    }

    # Re-run protection — skip if already executed within the last 24 hours
    $Rerun = Test-CIPPRerun -Tenant $Tenant -API 'AutoAddProxy' -Interval 86400
    if ($Rerun) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'AutoAddProxy recently executed. Skipping to prevent duplicate execution.' -sev Debug
        return $true
    }

    # Use the reporting DB cache for both accepted domains and mailboxes
    $Domains = @(New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains' | Select-Object -ExpandProperty DomainName)
    if ($Domains.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No cached accepted domains found. Ensure the ExoAcceptedDomains cache has been populated.' -sev Error
        return
    }

    $AllMailboxes = @(New-CIPPDbRequest -TenantFilter $Tenant -Type 'Mailboxes')
    if ($AllMailboxes.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No cached mailboxes found. Ensure the mailbox cache has been populated.' -sev Error
        return
    }

    # Build a list of all email addresses per mailbox from the cache fields
    # Cache stores: primarySmtpAddress, AdditionalEmailAddresses (comma-separated lowercase smtp aliases)
    $MissingProxies = 0
    foreach ($Domain in $Domains) {
        $ProcessMailboxes = @($AllMailboxes | Where-Object {
            $AllAddresses = @($_.primarySmtpAddress)
            if (-not [string]::IsNullOrWhiteSpace($_.AdditionalEmailAddresses)) {
                $AllAddresses += @($_.AdditionalEmailAddresses -split ',\s*')
            }
            $HasDomain = $AllAddresses | Where-Object { $_ -like "*@$Domain" }
            -not $HasDomain
        })
        $MissingProxies += $ProcessMailboxes.Count
    }

    $StateIsCorrect = $MissingProxies -eq 0
    $ExpectedValue = [PSCustomObject]@{
        MissingProxies = 0
    }
    $CurrentValue = [PSCustomObject]@{
        MissingProxies = $MissingProxies
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AutoAddProxy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AutoAddProxy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have proxy addresses for all domains' -sev Info
        } else {
            Write-StandardsAlert -message "There are $MissingProxies missing proxy addresses across all mailboxes" -object @{MissingProxies = $MissingProxies } -tenant $Tenant -standardName 'AutoAddProxy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "There are $MissingProxies missing proxy addresses across all mailboxes" -sev Info
        }
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes already have proxy addresses for all domains' -sev Info
        } else {
            foreach ($Domain in $Domains) {
                $ProcessMailboxes = @($AllMailboxes | Where-Object {
                    $AllAddresses = @($_.primarySmtpAddress)
                    if (-not [string]::IsNullOrWhiteSpace($_.AdditionalEmailAddresses)) {
                        $AllAddresses += @($_.AdditionalEmailAddresses -split ',\s*')
                    }
                    $HasDomain = $AllAddresses | Where-Object { $_ -like "*@$Domain" }
                    -not $HasDomain
                })

                $bulkRequest = foreach ($Mailbox in $ProcessMailboxes) {
                    if ([string]::IsNullOrWhiteSpace($Mailbox.UPN)) { continue }
                    $LocalPart = $Mailbox.UPN -split '@' | Select-Object -First 1
                    $NewAlias = "$LocalPart@$Domain"
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{
                                Identity       = $Mailbox.UPN
                                EmailAddresses = @{
                                    '@odata.type' = '#Exchange.GenericHashTable'
                                    Add           = "smtp:$NewAlias"
                                }
                            }
                        }
                    }
                }
                if ($bulkRequest) {
                    $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($bulkRequest)
                    foreach ($Result in $BatchResults) {
                        if ($Result.error) {
                            $ErrorMessage = Get-CippException -Exception $Result.error
                            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply proxy address to $($Result.error.target) Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                        }
                    }
                }
            }
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Added missing proxy addresses to mailboxes' -sev Info
        }
    }
}

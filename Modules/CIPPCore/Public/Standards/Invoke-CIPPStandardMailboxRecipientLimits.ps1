function Invoke-CIPPStandardMailboxRecipientLimits {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MailboxRecipientLimits
    .SYNOPSIS
        (Label) Set Mailbox Recipient Limits
    .DESCRIPTION
        (Helptext) Sets the maximum number of recipients that can be specified in the To, Cc, and Bcc fields of a message for all mailboxes in the tenant.
        (DocsDescription) This standard configures the recipient limits for all mailboxes in the tenant. The recipient limit determines the maximum number of recipients that can be specified in the To, Cc, and Bcc fields of a message. This helps prevent spam and manage email flow.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Controls how many recipients employees can include in a single email, helping prevent spam distribution and managing email server load. This security measure protects against both accidental mass mailings and potential abuse while ensuring legitimate business communications can still reach necessary recipients.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.MailboxRecipientLimits.RecipientLimit","label":"Recipient Limit","defaultValue":500}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-05-28
        POWERSHELLEQUIVALENT
            Set-Mailbox -RecipientLimits
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'MailboxRecipientLimits' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Input validation
    if ([Int32]$Settings.RecipientLimit -lt 0 -or [Int32]$Settings.RecipientLimit -gt 10000) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'MailboxRecipientLimits: Invalid RecipientLimit parameter set. Must be between 0 and 10000.' -sev Error
        return
    }

    # Get mailbox plans first
    try {
        $MailboxPlans = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxPlan' -cmdParams @{ ResultSize = 'Unlimited' }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the MailboxRecipientLimits state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Create a hashtable of mailbox plans for quick lookup
    $MailboxPlanLookup = @{}
    foreach ($Plan in $MailboxPlans) {
        $MailboxPlanLookup[$Plan.Guid] = $Plan
    }

    # Get mailboxes that need updating (either different from target limit or have "Unlimited" set)
    $Requests = @(
        @{
            CmdletInput = @{
                CmdletName = 'Get-Mailbox'
                Parameters = @{
                    ResultSize = 'Unlimited'
                    Filter     = "RecipientLimits -ne '$($Settings.RecipientLimit)' -or RecipientLimits -eq 'Unlimited'"
                }
            }
        }
    )

    $Mailboxes = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $Requests

    # Skip processing entirely if no mailboxes returned - most performant approach
    $MailboxResults = @()
    $MailboxesToUpdate = @()
    $MailboxesWithPlanIssues = @()

    if ($null -ne $Mailboxes -and @($Mailboxes).Count -gt 0) {
        # Process mailboxes and categorize them based on their plan limits
        $MailboxResults = foreach ($Mailbox in @($Mailboxes)) {
            if ($Mailbox.UserPrincipalName -like 'DiscoverySearchMailbox*' -or $Mailbox.UserPrincipalName -like 'SystemMailbox*') {
                continue
            }
            # Safe hashtable lookup - check if MailboxPlanId exists and is not null
            $Plan = $null
            if ($Mailbox.MailboxPlanId -and $MailboxPlanLookup.ContainsKey($Mailbox.MailboxPlanId)) {
                $Plan = $MailboxPlanLookup[$Mailbox.MailboxPlanId]
            }

            if ($Plan) {
                $PlanMaxRecipients = $Plan.MaxRecipientsPerMessage

                # If mailbox has "Unlimited" set but has a plan, use the plan's limit as the current limit
                $CurrentLimit = if ($Mailbox.RecipientLimits -eq 'Unlimited') {
                    $PlanMaxRecipients
                } else {
                    $Mailbox.RecipientLimits
                }

                if ($Settings.RecipientLimit -gt $PlanMaxRecipients) {
                    [PSCustomObject]@{
                        Type         = 'PlanIssue'
                        Mailbox      = $Mailbox
                        CurrentLimit = $CurrentLimit
                        PlanLimit    = $PlanMaxRecipients
                        PlanName     = $Plan.DisplayName
                    }
                } elseif ($CurrentLimit -ne $Settings.RecipientLimit) {
                    [PSCustomObject]@{
                        Type    = 'ToUpdate'
                        Mailbox = $Mailbox
                    }
                }
            } elseif ($Mailbox.RecipientLimits -ne $Settings.RecipientLimit) {
                [PSCustomObject]@{
                    Type    = 'ToUpdate'
                    Mailbox = $Mailbox
                }
            }
        }

        # Separate mailboxes into their respective categories only if we have results
        $MailboxesToUpdate = $MailboxResults | Where-Object { $_.Type -eq 'ToUpdate' } | Select-Object -ExpandProperty Mailbox
        $PlanIssueResults = $MailboxResults | Where-Object { $_.Type -eq 'PlanIssue' }
        $MailboxesWithPlanIssues = foreach ($Issue in $PlanIssueResults) {
            [PSCustomObject]@{
                Identity     = $Issue.Mailbox.Identity
                CurrentLimit = $Issue.CurrentLimit
                PlanLimit    = $Issue.PlanLimit
                PlanName     = $Issue.PlanName
            }
        }
    }

    # Remediation
    if ($Settings.remediate -eq $true) {
        if ($MailboxesWithPlanIssues.Count -gt 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Found $($MailboxesWithPlanIssues.Count) mailboxes where the requested recipient limit ($($Settings.RecipientLimit)) exceeds their mailbox plan limit. These mailboxes will not be updated." -sev Info
            foreach ($Mailbox in $MailboxesWithPlanIssues) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailbox $($Mailbox.Identity) has plan $($Mailbox.PlanName) with maximum limit of $($Mailbox.PlanLimit)" -sev Info
            }
        }

        if ($MailboxesToUpdate.Count -gt 0) {
            try {
                # Create detailed log data for audit trail
                $MailboxChanges = foreach ($Mailbox in $MailboxesToUpdate) {
                    $CurrentLimit = if ($Mailbox.RecipientLimits -eq 'Unlimited') { 'Unlimited' } else { $Mailbox.RecipientLimits }
                    @{
                        Identity           = $Mailbox.Identity
                        DisplayName        = $Mailbox.DisplayName
                        PrimarySmtpAddress = $Mailbox.PrimarySmtpAddress
                        CurrentLimit       = $CurrentLimit
                        NewLimit           = $Settings.RecipientLimit
                    }
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updating recipient limits to $($Settings.RecipientLimit) for $($MailboxesToUpdate.Count) mailboxes" -sev Info -LogData $MailboxChanges

                # Create batch requests for mailbox updates
                $UpdateRequests = foreach ($Mailbox in $MailboxesToUpdate) {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{
                                Identity        = $Mailbox.Identity
                                RecipientLimits = $Settings.RecipientLimit
                            }
                        }
                    }
                }

                # Execute batch update
                $null = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $UpdateRequests
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully applied recipient limits to $($MailboxesToUpdate.Count) mailboxes" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set recipient limits. $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All mailboxes already have the correct recipient limit of $($Settings.RecipientLimit)" -sev Info
        }
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($MailboxesToUpdate.Count -eq 0 -and $MailboxesWithPlanIssues.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All mailboxes have the correct recipient limit of $($Settings.RecipientLimit)" -sev Info
        } else {
            # Create structured alert data
            $AlertData = @{
                RequestedLimit          = $Settings.RecipientLimit
                MailboxesToUpdate       = @()
                MailboxesWithPlanIssues = @()
            }

            # Use Generic List for efficient object collection
            $AlertObjects = [System.Collections.Generic.List[Object]]::new()

            # Add mailboxes that need updating
            if ($MailboxesToUpdate.Count -gt 0) {
                $AlertData.MailboxesToUpdate = foreach ($Mailbox in $MailboxesToUpdate) {
                    $CurrentLimit = if ($Mailbox.RecipientLimits -eq 'Unlimited') { 'Unlimited' } else { $Mailbox.RecipientLimits }
                    @{
                        Identity           = $Mailbox.Identity
                        DisplayName        = $Mailbox.DisplayName
                        PrimarySmtpAddress = $Mailbox.PrimarySmtpAddress
                        CurrentLimit       = $CurrentLimit
                        RequiredLimit      = $Settings.RecipientLimit
                    }
                }
                # Add to alert objects list efficiently
                foreach ($Mailbox in $MailboxesToUpdate) {
                    $AlertObjects.Add($Mailbox)
                }
            }

            # Add mailboxes with plan issues
            if ($MailboxesWithPlanIssues.Count -gt 0) {
                $AlertData.MailboxesWithPlanIssues = foreach ($Issue in $MailboxesWithPlanIssues) {
                    @{
                        Identity       = $Issue.Identity
                        CurrentLimit   = $Issue.CurrentLimit
                        PlanLimit      = $Issue.PlanLimit
                        PlanName       = $Issue.PlanName
                        RequestedLimit = $Settings.RecipientLimit
                    }
                }
                # Add to alert objects list efficiently
                foreach ($Mailbox in $MailboxesWithPlanIssues) {
                    $AlertObjects.Add($Mailbox)
                }
            }

            # Build alert message efficiently
            $AlertMessage = if ($MailboxesWithPlanIssues.Count -gt 0) {
                "Found $($MailboxesToUpdate.Count) mailboxes with incorrect recipient limits and $($MailboxesWithPlanIssues.Count) mailboxes where the requested limit exceeds their mailbox plan limit"
            } else {
                "Found $($MailboxesToUpdate.Count) mailboxes with incorrect recipient limits"
            }

            Write-StandardsAlert -message $AlertMessage -object $AlertObjects.ToArray() -tenant $Tenant -standardName 'MailboxRecipientLimits' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info -LogData $AlertData
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        $ReportData = @{
            MailboxesToUpdate       = $MailboxesToUpdate
            MailboxesWithPlanIssues = $MailboxesWithPlanIssues
        }
        Add-CIPPBPAField -FieldName 'MailboxRecipientLimits' -FieldValue $ReportData -StoreAs json -Tenant $Tenant

        $CurrentValue = @{
            MailboxesToUpdate       = @($MailboxesToUpdate)
            MailboxesWithPlanIssues = @($MailboxesWithPlanIssues)
        }
        $ExpectedValue = @{
            MailboxesToUpdate       = @()
            MailboxesWithPlanIssues = @()
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.MailboxRecipientLimits' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}

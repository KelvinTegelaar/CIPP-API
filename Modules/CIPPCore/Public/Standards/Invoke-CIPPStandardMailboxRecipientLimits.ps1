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
    #>

    param($Tenant, $Settings)

    # Input validation
    if ([Int32]$Settings.RecipientLimit -lt 0 -or [Int32]$Settings.RecipientLimit -gt 10000) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'MailboxRecipientLimits: Invalid RecipientLimit parameter set. Must be between 0 and 10000.' -sev Error
        return
    }

    # Get mailbox plans first
    $MailboxPlans = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxPlan' -cmdParams @{ ResultSize = 'Unlimited' }

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

    # Process mailboxes and categorize them based on their plan limits
    $MailboxResults = $Mailboxes | ForEach-Object {
        $Mailbox = $_
        $Plan = $MailboxPlanLookup[$Mailbox.MailboxPlanId]
        
        if ($Plan) {
            $PlanMaxRecipients = $Plan.MaxRecipientsPerMessage
            
            # If mailbox has "Unlimited" set but has a plan, use the plan's limit as the current limit
            $CurrentLimit = if ($Mailbox.RecipientLimits -eq 'Unlimited') {
                $PlanMaxRecipients
            }
            else {
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
            }
            elseif ($CurrentLimit -ne $Settings.RecipientLimit) {
                [PSCustomObject]@{
                    Type    = 'ToUpdate'
                    Mailbox = $Mailbox
                }
            }
        }
        elseif ($Mailbox.RecipientLimits -ne $Settings.RecipientLimit) {
            [PSCustomObject]@{
                Type    = 'ToUpdate'
                Mailbox = $Mailbox
            }
        }
    }

    # Separate mailboxes into their respective categories
    $MailboxesToUpdate = $MailboxResults | Where-Object { $_.Type -eq 'ToUpdate' } | Select-Object -ExpandProperty Mailbox
    $MailboxesWithPlanIssues = $MailboxResults | Where-Object { $_.Type -eq 'PlanIssue' } | ForEach-Object {
        [PSCustomObject]@{
            Identity     = $_.Mailbox.Identity
            CurrentLimit = $_.CurrentLimit
            PlanLimit    = $_.PlanLimit
            PlanName     = $_.PlanName
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
                # Create batch requests for mailbox updates
                $UpdateRequests = $MailboxesToUpdate | ForEach-Object {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{
                                Identity        = $_.Identity
                                RecipientLimits = $Settings.RecipientLimit
                            }
                        }
                    }
                }

                # Execute batch update
                $null = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $UpdateRequests
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set recipient limits to $($Settings.RecipientLimit) for $($MailboxesToUpdate.Count) mailboxes" -sev Info
            }
            catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set recipient limits. $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
        else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All mailboxes already have the correct recipient limit of $($Settings.RecipientLimit)" -sev Info
        }
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($MailboxesToUpdate.Count -eq 0 -and $MailboxesWithPlanIssues.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All mailboxes have the correct recipient limit of $($Settings.RecipientLimit)" -sev Info
        }
        else {
            $AlertMessage = "Found $($MailboxesToUpdate.Count) mailboxes with incorrect recipient limits"
            if ($MailboxesWithPlanIssues.Count -gt 0) {
                $AlertMessage += " and $($MailboxesWithPlanIssues.Count) mailboxes where the requested limit exceeds their mailbox plan limit"
            }
            Write-StandardsAlert -message $AlertMessage -object ($MailboxesToUpdate + $MailboxesWithPlanIssues) -tenant $Tenant -standardName 'MailboxRecipientLimits' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        $ReportData = @{
            MailboxesToUpdate       = $MailboxesToUpdate
            MailboxesWithPlanIssues = $MailboxesWithPlanIssues
        }
        Add-CIPPBPAField -FieldName 'MailboxRecipientLimits' -FieldValue $ReportData -StoreAs json -Tenant $Tenant

        if ($MailboxesToUpdate.Count -eq 0 -and $MailboxesWithPlanIssues.Count -eq 0) {
            $FieldValue = $true
        }
        else {
            $FieldValue = $ReportData
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.MailboxRecipientLimits' -FieldValue $FieldValue -Tenant $Tenant
    }
} 
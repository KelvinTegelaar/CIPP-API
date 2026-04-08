function Invoke-CIPPStandardDisableCalendarTentative {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableCalendarTentative
    .SYNOPSIS
        (Label) Disable auto-tentative calendar invites for all mailboxes
    .DESCRIPTION
        (Helptext) Sets AutomateProcessing to None on all mailboxes, preventing calendar invites from automatically appearing as tentative in Outlook.
        (DocsDescription) Sets AutomateProcessing to None on all mailboxes, preventing calendar invites from automatically appearing as tentative in Outlook. This applies to all mailbox types including user and shared mailboxes.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Prevents calendar invites from automatically populating as tentative in Outlook for all mailboxes. This reduces the risk of unintended calendar visibility and ensures users explicitly accept or decline meeting invitations.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2026-04-08
        POWERSHELLEQUIVALENT
            Set-CalendarProcessing -Identity <mailbox> -AutomateProcessing None
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableCalendarTentative' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE')

    if ($TestResult -eq $false) {
        return $true
    }

    $AllMailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ ResultSize = 'Unlimited' }

    $MailboxesNotCompliant = foreach ($Mailbox in $AllMailboxes) {
        $CalProc = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-CalendarProcessing' -cmdParams @{ Identity = $Mailbox.UserPrincipalName }
        if ($CalProc.AutomateProcessing -ne 'None') {
            $Mailbox
        }
    }

    if ($Settings.remediate -eq $true) {

        if ($null -eq $MailboxesNotCompliant) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'AutomateProcessing is already set to None for all mailboxes' -sev Info
        } else {
            foreach ($Mailbox in $MailboxesNotCompliant) {
                try {
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-CalendarProcessing' -cmdParams @{ Identity = $Mailbox.UserPrincipalName; AutomateProcessing = 'None' }
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set AutomateProcessing to None for $($Mailbox.UserPrincipalName)" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set AutomateProcessing for $($Mailbox.UserPrincipalName). Error: $ErrorMessage" -sev Error
                }
            }
        }

    }

    if ($Settings.alert -eq $true) {

        if ($MailboxesNotCompliant) {
            $Object = $MailboxesNotCompliant | Select-Object -Property UserPrincipalName
            Write-StandardsAlert -message "Mailboxes with AutomateProcessing not set to None: $($MailboxesNotCompliant.Count)" -object $Object -tenant $Tenant -standardName 'DisableCalendarTentative' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailboxes with AutomateProcessing not set to None: $($MailboxesNotCompliant.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have AutomateProcessing set to None' -sev Info
        }

    }

    if ($Settings.report -eq $true) {
        $filtered = $MailboxesNotCompliant | Select-Object -Property UserPrincipalName
        $stateReport = $filtered ? $filtered : @()

        $CurrentValue = [PSCustomObject]@{
            AutomateProcessingNotNone = @($stateReport)
        }
        $ExpectedValue = [PSCustomObject]@{
            AutomateProcessingNotNone = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableCalendarTentative' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableCalendarTentative' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }

}

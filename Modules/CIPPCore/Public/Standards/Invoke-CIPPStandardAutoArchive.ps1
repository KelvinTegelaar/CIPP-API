function Invoke-CIPPStandardAutoArchive {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AutoArchive
    .SYNOPSIS
        (Label) Configure Auto-Archiving Threshold
    .DESCRIPTION
        (Helptext) Configures the auto-archiving threshold percentage for the tenant. When a mailbox exceeds this threshold, the oldest items are automatically moved to the archive mailbox. Archive must be enabled manually or via the CIPP standard 'Enable Online Archive for all users'. More information can be found in [Microsoft's documentation.](https://learn.microsoft.com/en-us/exchange/security-and-compliance/messaging-records-management/auto-archiving)
        (DocsDescription) Configures the auto-archiving threshold at the organization level. Auto-archiving automatically moves the oldest items from a user's primary mailbox to their archive mailbox when mailbox usage exceeds the configured threshold percentage. This prevents mail flow disruptions caused by full mailboxes. Valid range is 80-100, where 100 disables auto-archiving for the tenant. More information can be found in [Microsoft's documentation.](https://learn.microsoft.com/en-us/exchange/security-and-compliance/messaging-records-management/auto-archiving)
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Configures automatic archiving of mailbox items when storage approaches capacity, preventing email delivery failures due to full mailboxes. This proactive storage management ensures business continuity and reduces helpdesk tickets related to mailbox quota issues.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.AutoArchive.AutoArchivingThresholdPercentage","label":"Auto-Archiving Threshold Percentage (80-100, default 96, 100 disables)","defaultValue":96}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-12-11
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -AutoArchivingThresholdPercentage 80-100
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'AutoArchive' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    }

    # Get the threshold value from settings
    $DesiredThreshold = [int]($Settings.AutoArchivingThresholdPercentage)

    # Validate the threshold is within valid range
    if ($DesiredThreshold -lt 80 -or $DesiredThreshold -gt 100) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Invalid AutoArchivingThresholdPercentage value: $DesiredThreshold. Must be between 80 and 100." -Sev Error
        return
    }

    try {
        $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' -Select 'AutoArchivingThresholdPercentage').AutoArchivingThresholdPercentage
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the AutoArchive state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    $CorrectState = $CurrentState -eq $DesiredThreshold

    $ExpectedValue = [PSCustomObject]@{
        AutoArchivingThresholdPercentage = $DesiredThreshold
    }
    $CurrentValue = [PSCustomObject]@{
        AutoArchivingThresholdPercentage = $CurrentState
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CorrectState) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Auto-archiving threshold is already set to $CurrentState%." -Sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ AutoArchivingThresholdPercentage = $DesiredThreshold }
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Auto-archiving threshold has been set to $DesiredThreshold%." -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set auto-archiving threshold. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CorrectState) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Auto-archiving threshold is correctly set to $CurrentState%." -Sev Info
        } else {
            Write-StandardsAlert -message "Auto-archiving threshold is set to $CurrentState% but should be $DesiredThreshold%." -object @{ CurrentThreshold = $CurrentState; DesiredThreshold = $DesiredThreshold } -tenant $Tenant -standardName 'AutoArchive' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Auto-archiving threshold is set to $CurrentState% but should be $DesiredThreshold%." -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AutoArchive' -FieldValue $CorrectState -StoreAs bool -Tenant $Tenant

        if ($CorrectState) {
            $FieldValue = $true
        } else {
            $FieldValue = @{ CurrentThreshold = $CurrentState; DesiredThreshold = $DesiredThreshold }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.AutoArchive' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}

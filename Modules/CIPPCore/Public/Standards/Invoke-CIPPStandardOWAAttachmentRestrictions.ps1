function Invoke-CIPPStandardOWAAttachmentRestrictions {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) OWAAttachmentRestrictions
    .SYNOPSIS
        (Label) Restrict Email Attachments on Unmanaged Devices
    .DESCRIPTION
        (Helptext) Restricts how users on unmanaged devices can interact with email attachments in Outlook on the web and new Outlook for Windows. Prevents downloading attachments or blocks viewing them entirely.
        (DocsDescription) This standard configures the OWA mailbox policy to restrict access to email attachments on unmanaged devices. Users can be prevented from downloading attachments (but can view/edit via Office Online) or blocked from seeing attachments entirely. This helps prevent data exfiltration through email attachments on devices not managed by the organization.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS M365 5.0 (6.1.2)"
            "Security"
            "NIST CSF 2.0 (PR.AA-05)"
        EXECUTIVETEXT
            Restricts access to email attachments on personal or unmanaged devices while allowing full functionality on corporate-managed devices. This security measure prevents data theft through email attachments while maintaining productivity for employees using approved company devices.
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"standards.OWAAttachmentRestrictions.ConditionalAccessPolicy","label":"Attachment Restriction Policy","options":[{"label":"Read Only (View/Edit via Office Online, no download)","value":"ReadOnly"},{"label":"Read Only Plus Attachments Blocked (Cannot see attachments)","value":"ReadOnlyPlusAttachmentsBlocked"}],"defaultValue":"ReadOnlyPlusAttachmentsBlocked"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-08-22
        POWERSHELLEQUIVALENT
            Set-OwaMailboxPolicy -Identity "OwaMailboxPolicy-Default" -ConditionalAccessPolicy ReadOnlyPlusAttachmentsBlocked
        RECOMMENDEDBY
            "Microsoft Zero Trust"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'OWAAttachmentRestrictions' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    # Input validation
    $ValidPolicies = @('ReadOnly', 'ReadOnlyPlusAttachmentsBlocked')
    if ($Settings.ConditionalAccessPolicy.value -notin $ValidPolicies) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "OWAAttachmentRestrictions: Invalid ConditionalAccessPolicy parameter set. Must be one of: $($ValidPolicies -join ', ')" -sev Error
        return
    }

    try {
        # Get the default OWA mailbox policy
        $CurrentPolicy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OwaMailboxPolicy' -cmdParams @{ Identity = 'OwaMailboxPolicy-Default' }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the OWA Attachment Restrictions state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $StateIsCorrect = $CurrentPolicy.ConditionalAccessPolicy -eq $Settings.ConditionalAccessPolicy.value

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "OWA attachment restrictions are already set to $($Settings.ConditionalAccessPolicy)" -sev Info
        } else {
            try {
                $cmdParams = @{
                    Identity                = 'OwaMailboxPolicy-Default'
                    ConditionalAccessPolicy = $Settings.ConditionalAccessPolicy.value
                }

                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OwaMailboxPolicy' -cmdParams $cmdParams

                $PolicyDescription = switch ($Settings.ConditionalAccessPolicy.value) {
                    'ReadOnly' { 'Read Only (users can view/edit attachments via Office Online but cannot download)' }
                    'ReadOnlyPlusAttachmentsBlocked' { 'Read Only Plus Attachments Blocked (users cannot see attachments at all)' }
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set OWA attachment restrictions to: $PolicyDescription" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set OWA attachment restrictions. $($ErrorMessage.NormalizedError)" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            $PolicyDescription = switch ($Settings.ConditionalAccessPolicy.value) {
                'ReadOnly' { 'Read Only (view/edit via Office Online, no download)' }
                'ReadOnlyPlusAttachmentsBlocked' { 'Read Only Plus Attachments Blocked (cannot see attachments)' }
            }
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "OWA attachment restrictions are correctly set to: $PolicyDescription" -sev Info
        } else {
            $CurrentDescription = switch ($CurrentPolicy.ConditionalAccessPolicy) {
                'ReadOnly' { 'Read Only (view/edit via Office Online, no download)' }
                'ReadOnlyPlusAttachmentsBlocked' { 'Read Only Plus Attachments Blocked (cannot see attachments)' }
                $null { 'Not configured (full access to attachments)' }
                default { $CurrentPolicy.ConditionalAccessPolicy }
            }

            $RequiredDescription = switch ($Settings.ConditionalAccessPolicy.value) {
                'ReadOnly' { 'Read Only (view/edit via Office Online, no download)' }
                'ReadOnlyPlusAttachmentsBlocked' { 'Read Only Plus Attachments Blocked (cannot see attachments)' }
            }

            $AlertMessage = "OWA attachment restrictions are set to '$CurrentDescription' but should be '$RequiredDescription'"
            Write-StandardsAlert -message $AlertMessage -object @{
                CurrentPolicy       = $CurrentPolicy.ConditionalAccessPolicy
                RequiredPolicy      = $Settings.ConditionalAccessPolicy
                PolicyName          = $CurrentPolicy.Name
                CurrentDescription  = $CurrentDescription
                RequiredDescription = $RequiredDescription
            } -tenant $Tenant -standardName 'OWAAttachmentRestrictions' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        if ($StateIsCorrect) {
            Set-CIPPStandardsCompareField -FieldName 'standards.OWAAttachmentRestrictions' -FieldValue $true -TenantFilter $Tenant
            Add-CIPPBPAField -FieldName 'OWAAttachmentRestrictions' -FieldValue $true -StoreAs bool -Tenant $Tenant
        } else {
            $ReportData = @{
                CurrentPolicy  = $CurrentPolicy.ConditionalAccessPolicy
                RequiredPolicy = $Settings.ConditionalAccessPolicy.value
                PolicyName     = $CurrentPolicy.Name
                IsCompliant    = $false
                Description    = 'OWA attachment restrictions not properly configured for unmanaged devices'
            }
            Set-CIPPStandardsCompareField -FieldName 'standards.OWAAttachmentRestrictions' -FieldValue $ReportData -TenantFilter $Tenant
            Add-CIPPBPAField -FieldName 'OWAAttachmentRestrictions' -FieldValue $ReportData -StoreAs json -Tenant $Tenant
        }
    }
}

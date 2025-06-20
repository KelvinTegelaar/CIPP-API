function Invoke-CIPPStandardDeployMailContact {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DeployMailContact
    .SYNOPSIS
        (Label) Deploy Mail Contact
    .DESCRIPTION
        (Helptext) Creates a new mail contact in Exchange Online across all selected tenants. The contact will be visible in the Global Address List.
        (DocsDescription) This standard creates a new mail contact in Exchange Online. Mail contacts are useful for adding external email addresses to your organization's address book. They can be used for distribution lists, shared mailboxes, and other collaboration scenarios.
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.DeployMailContact.ExternalEmailAddress","label":"External Email Address","required":true}
            {"type":"textField","name":"standards.DeployMailContact.DisplayName","label":"Display Name","required":true}
            {"type":"textField","name":"standards.DeployMailContact.FirstName","label":"First Name","required":false}
            {"type":"textField","name":"standards.DeployMailContact.LastName","label":"Last Name","required":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-03-19
        POWERSHELLEQUIVALENT
            New-MailContact
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    # Input validation
    if ([string]::IsNullOrWhiteSpace($Settings.DisplayName)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'DeployMailContact: DisplayName cannot be empty or just whitespace.' -sev Error
        return
    }

    try {
        $null = [System.Net.Mail.MailAddress]::new($Settings.ExternalEmailAddress)
    }
    catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "DeployMailContact: Invalid email address format: $($Settings.ExternalEmailAddress)" -sev Error
        return
    }

    # Prepare contact data for reuse
    $ContactData = @{
        DisplayName          = $Settings.DisplayName
        ExternalEmailAddress = $Settings.ExternalEmailAddress
        FirstName            = $Settings.FirstName
        LastName             = $Settings.LastName
    }

    # Check if contact already exists
    try {
        $ExistingContact = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailContact' -cmdParams @{
            Identity    = $Settings.ExternalEmailAddress
            ErrorAction = 'Stop'
        }
    }
    catch {
        if ($_.Exception.Message -like "*couldn't be found*") {
            $ExistingContact = $null
        }
        else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Error checking for existing mail contact: $(Get-CippException -Exception $_).NormalizedError" -sev Error
            return
        }
    }

    # Remediation
    if ($Settings.remediate -eq $true -and -not $ExistingContact) {
        try {
            $NewContactParams = $ContactData.Clone()
            $NewContactParams.Name = $Settings.DisplayName
            $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-MailContact' -cmdParams $NewContactParams
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully created mail contact $($Settings.DisplayName) with email $($Settings.ExternalEmailAddress)" -sev Info
        }
        catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not create mail contact. $(Get-CippException -Exception $_).NormalizedError" -sev Error
        }
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($ExistingContact) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mail contact $($Settings.DisplayName) already exists" -sev Info
        }
        else {
            Write-StandardsAlert -message "Mail contact $($Settings.DisplayName) needs to be created" -object $ContactData -tenant $Tenant -standardName 'DeployMailContact' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mail contact $($Settings.DisplayName) needs to be created" -sev Info
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        $ReportData = $ContactData.Clone()
        $ReportData.Exists = [bool]$ExistingContact
        Add-CIPPBPAField -FieldName 'DeployMailContact' -FieldValue $ReportData -StoreAs json -Tenant $Tenant
        Set-CIPPStandardsCompareField -FieldName 'standards.DeployMailContact' -FieldValue $($ExistingContact ? $true : $ReportData) -Tenant $Tenant
    }
}

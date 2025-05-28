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
            2025-05-28
        POWERSHELLEQUIVALENT
            New-MailContact
        RECOMMENDEDBY
            "CIPP"
    #>

    param($Tenant, $Settings)

    # Input validation
    if (-not $Settings.ExternalEmailAddress -or -not $Settings.DisplayName) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'DeployMailContact: ExternalEmailAddress and DisplayName are required parameters.' -sev Error
        return
    }

    # Validate email address format
    try {
        $null = [System.Net.Mail.MailAddress]::new($Settings.ExternalEmailAddress)
    }
    catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "DeployMailContact: Invalid email address format: $($Settings.ExternalEmailAddress)" -sev Error
        return
    }

    # Check if contact already exists
    try {
        $ExistingContact = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailContact' -cmdParams @{
            Identity    = $Settings.ExternalEmailAddress
            ErrorAction = 'Stop'
        }
    }
    catch {
        # If the error is that the contact wasn't found, that's expected and we can proceed
        if ($_.Exception.Message -like "*couldn't be found*") {
            $ExistingContact = $null
        }
        else {
            # For any other error, we should log it and return
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Error checking for existing mail contact: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            return
        }
    }

    if ($ExistingContact) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mail contact with email $($Settings.ExternalEmailAddress) already exists" -sev Info
        return
    }

    # Remediation
    if ($Settings.remediate -eq $true) {
        try {
            $NewContactParams = @{
                ExternalEmailAddress = $Settings.ExternalEmailAddress
                DisplayName          = $Settings.DisplayName
                Name                 = $Settings.DisplayName
            }

            # Add optional parameters if provided
            if ($Settings.FirstName) { $NewContactParams.FirstName = $Settings.FirstName }
            if ($Settings.LastName) { $NewContactParams.LastName = $Settings.LastName }

            $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-MailContact' -cmdParams $NewContactParams
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully created mail contact $($Settings.DisplayName) with email $($Settings.ExternalEmailAddress)" -sev Info
        }
        catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not create mail contact. $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($ExistingContact) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mail contact $($Settings.DisplayName) already exists" -sev Info
        }
        else {
            Write-StandardsAlert -message "Mail contact $($Settings.DisplayName) needs to be created" -object @{
                DisplayName          = $Settings.DisplayName
                ExternalEmailAddress = $Settings.ExternalEmailAddress
                FirstName            = $Settings.FirstName
                LastName             = $Settings.LastName
            } -tenant $Tenant -standardName 'DeployMailContact' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mail contact $($Settings.DisplayName) needs to be created" -sev Info
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        $ReportData = @{
            DisplayName          = $Settings.DisplayName
            ExternalEmailAddress = $Settings.ExternalEmailAddress
            FirstName            = $Settings.FirstName
            LastName             = $Settings.LastName
            Exists               = [bool]$ExistingContact
        }
        Add-CIPPBPAField -FieldName 'DeployMailContact' -FieldValue $ReportData -StoreAs json -Tenant $Tenant

        if ($ExistingContact) {
            $FieldValue = $true
        }
        else {
            $FieldValue = $ReportData
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.DeployMailContact' -FieldValue $FieldValue -Tenant $Tenant
    }
} 
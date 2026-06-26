function Invoke-CIPPStandardDeployContactTemplates {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DeployContactTemplates
    .SYNOPSIS
        (Label) Deploy Mail Contact Template
    .DESCRIPTION
        (Helptext) Creates new mail contacts in Exchange Online across all selected tenants based on the selected templates. The contact will be visible in the Global Address List unless hidden.
        (DocsDescription) This standard creates new mail contacts in Exchange Online based on the selected templates. Mail contacts are useful for adding external email addresses to your organization's address book. They can be used for distribution lists, shared mailboxes, and other collaboration scenarios.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Deploys standardized external contact templates across all company locations, ensuring consistent communication channels with key external partners, vendors, and stakeholders. This streamlines contact management and maintains uniform business relationships.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"label":"Select Mail Contact Templates","name":"standards.DeployContactTemplates.templateIds","api":{"url":"/api/ListContactTemplates","labelField":"name","valueField":"GUID","queryKey":"Contact Templates"}}
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-05-31
        POWERSHELLEQUIVALENT
            New-MailContact
        RECOMMENDEDBY
            "CIPP"
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DeployContactTemplates' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $APIName = 'Standards'



    # Helper function to get template by GUID
    function Get-ContactTemplate($TemplateGUID) {
        try {
            $Table = Get-CippTable -tablename 'templates'
            $Filter = "PartitionKey eq 'ContactTemplate' and RowKey eq '$TemplateGUID'"
            $StoredTemplate = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            if (-not $StoredTemplate) {
                Write-LogMessage -API $APIName -tenant $Tenant -message "Contact template with GUID $TemplateGUID not found" -sev Error
                return $null
            }

            return $StoredTemplate.JSON | ConvertFrom-Json
        } catch {
            Write-LogMessage -API $APIName -tenant $Tenant -message "Failed to retrieve template $TemplateGUID. Error: $($_.Exception.Message)" -sev Error
            return $null
        }
    }



    try {
        # Extract control flags from Settings
        $RemediateEnabled = [bool]$Settings.remediate
        $AlertEnabled = [bool]$Settings.alert
        $ReportEnabled = [bool]$Settings.report

        # Get templateIds array
        if (-not $Settings.templateIds -or $Settings.templateIds.Count -eq 0) {
            Write-LogMessage -API $APIName -tenant $Tenant -message 'DeployContactTemplate: No template IDs found in settings' -sev Error
            return 'No template IDs found in settings'
        }

        Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: Processing $($Settings.templateIds.Count) template(s)" -sev Info

        # Get the current contacts
        $CurrentContacts = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailContact' -ErrorAction Stop

        # Process each template in the templateIds array
        $CompareList = foreach ($TemplateItem in $Settings.templateIds) {
            try {
                # Get the template GUID directly from the value property
                $TemplateGUID = $TemplateItem.value

                if ([string]::IsNullOrWhiteSpace($TemplateGUID)) {
                    Write-LogMessage -API $APIName -tenant $Tenant -message 'DeployContactTemplate: TemplateGUID cannot be empty.' -sev Error
                    continue
                }

                # Fetch the template from storage
                $Template = Get-ContactTemplate -TemplateGUID $TemplateGUID
                if (-not $Template) {
                    continue
                }

                # Input validation for required fields
                if ([string]::IsNullOrWhiteSpace($Template.displayName)) {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: DisplayName cannot be empty for template $TemplateGUID." -sev Error
                    continue
                }

                if ([string]::IsNullOrWhiteSpace($Template.email)) {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: ExternalEmailAddress cannot be empty for template $TemplateGUID." -sev Error
                    continue
                }

                # Validate email address format
                try {
                    $null = [System.Net.Mail.MailAddress]::new($Template.email)
                } catch {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: Invalid email address format: $($Template.email)" -sev Error
                    continue
                }

                # Check if the contact already exists (using DisplayName as key)
                $ExistingContact = $CurrentContacts | Where-Object { $_.DisplayName -eq $Template.displayName }

                if ($ExistingContact) {
                    # Fetch extended properties (Company/City/Phone/etc. live on Get-Contact, not Get-MailContact)
                    $ExtendedContact = $null
                    try {
                        $ExtendedContact = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Contact' -cmdParams @{ Identity = $ExistingContact.Identity } -UseSystemMailbox $true -ErrorAction Stop
                    } catch {
                        Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: Failed to fetch extended contact properties for $($Template.displayName): $($_.Exception.Message)" -sev Warning
                    }

                    # Map template field => current value (null/empty when current source missing)
                    # ExternalEmailAddress comes back as "SMTP:foo@bar.com" — strip the prefix for comparison.
                    $CurrentEmail = $ExistingContact.ExternalEmailAddress -replace '^SMTP:', '' -replace '^smtp:', ''
                    $FieldMap = @(
                        @{ Template = 'email';         Current = $CurrentEmail }
                        @{ Template = 'firstName';     Current = $ExtendedContact.FirstName }
                        @{ Template = 'lastName';      Current = $ExtendedContact.LastName }
                        @{ Template = 'mailTip';       Current = $ExistingContact.MailTip }
                        @{ Template = 'hidefromGAL';   Current = $ExistingContact.HiddenFromAddressListsEnabled; IsBool = $true }
                        @{ Template = 'companyName';   Current = $ExtendedContact.Company }
                        @{ Template = 'state';         Current = $ExtendedContact.StateOrProvince }
                        @{ Template = 'streetAddress'; Current = $ExtendedContact.StreetAddress }
                        @{ Template = 'businessPhone'; Current = $ExtendedContact.Phone }
                        @{ Template = 'website';       Current = $ExtendedContact.WebPage }
                        @{ Template = 'jobTitle';      Current = $ExtendedContact.Title }
                        @{ Template = 'city';          Current = $ExtendedContact.City }
                        @{ Template = 'postalCode';    Current = $ExtendedContact.PostalCode }
                        @{ Template = 'country';       Current = $ExtendedContact.CountryOrRegion }
                        @{ Template = 'mobilePhone';   Current = $ExtendedContact.MobilePhone }
                    )

                    $Differences = [System.Collections.Generic.List[string]]::new()
                    foreach ($Field in $FieldMap) {
                        $TemplateValue = $Template.($Field.Template)
                        $CurrentValue = $Field.Current

                        if ($Field.IsBool) {
                            if ([bool]$TemplateValue -ne [bool]$CurrentValue) {
                                $Differences.Add($Field.Template)
                            }
                            continue
                        }

                        # Only compare if template specifies a value; empty template fields are not enforced.
                        if ([string]::IsNullOrWhiteSpace($TemplateValue)) { continue }

                        # Case-insensitive compare for email; exact for everything else.
                        $IsEmail = $Field.Template -eq 'email'
                        $Mismatch = if ($IsEmail) {
                            [string]::IsNullOrWhiteSpace($CurrentValue) -or -not $TemplateValue.Equals($CurrentValue, [System.StringComparison]::OrdinalIgnoreCase)
                        } else {
                            [string]::IsNullOrWhiteSpace($CurrentValue) -or $TemplateValue -ne $CurrentValue
                        }

                        if ($Mismatch) {
                            $Differences.Add($Field.Template)
                        }
                    }

                    $StateIsCorrect = $Differences.Count -eq 0
                    $Action = if ($StateIsCorrect) { 'None' } else { 'Update' }
                    $Missing = $false
                } else {
                    # Contact doesn't exist, needs to be created
                    $StateIsCorrect = $false
                    $Action = 'Create'
                    $Missing = $true
                    $Differences = $null
                }

                [PSCustomObject]@{
                    missing        = $Missing
                    StateIsCorrect = $StateIsCorrect
                    Action         = $Action
                    Template       = $Template
                    TemplateGUID   = $TemplateGUID
                    Differences    = $Differences
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $Message = "Failed to process template $TemplateGUID, Error: $ErrorMessage"
                Write-LogMessage -API $APIName -tenant $tenant -message $Message -sev 'Error'
                continue
            }
        }

        # Remediate each contact which needs to be created or updated
        if ($RemediateEnabled) {
            $ContactsToProcess = $CompareList | Where-Object { $_.StateIsCorrect -eq $false }

            if ($ContactsToProcess.Count -gt 0) {
                $ContactsToCreate = $ContactsToProcess | Where-Object { $_.Action -eq 'Create' }
                $ContactsToUpdate = $ContactsToProcess | Where-Object { $_.Action -eq 'Update' }

                Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: Processing $($ContactsToCreate.Count) new contacts, $($ContactsToUpdate.Count) existing contacts" -sev Info

                # First pass: Create new mail contacts and update existing ones
                $ProcessedContacts = [System.Collections.Generic.List[PSCustomObject]]::new()
                $ProcessingFailures = 0

                # Handle new contacts
                foreach ($Contact in $ContactsToCreate) {
                    try {
                        $Template = $Contact.Template

                        # Parameters for creating new contact
                        $NewContactParams = @{
                            displayName          = $Template.displayName
                            name                 = $Template.displayName
                            ExternalEmailAddress = $Template.email
                        }

                        # Add optional name fields if provided
                        if (![string]::IsNullOrWhiteSpace($Template.firstName)) {
                            $NewContactParams.FirstName = $Template.firstName
                        }
                        if (![string]::IsNullOrWhiteSpace($Template.lastName)) {
                            $NewContactParams.LastName = $Template.lastName
                        }

                        # Create the mail contact
                        $NewContact = New-ExoRequest -tenantid $Tenant -cmdlet 'New-MailContact' -cmdParams $NewContactParams -UseSystemMailbox $true

                        # Store contact info for second pass
                        $ProcessedContacts.Add([PSCustomObject]@{
                                Contact       = $Contact
                                ContactObject = $NewContact
                                Template      = $Template
                                IsNew         = $true
                            })
                    } catch {
                        $ProcessingFailures++
                        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                        Write-LogMessage -API $APIName -tenant $tenant -message "Failed to create contact $($Template.displayName): $ErrorMessage" -sev 'Error'
                    }
                }

                # Handle existing contacts - update their basic properties
                foreach ($Contact in $ContactsToUpdate) {
                    try {
                        $Template = $Contact.Template
                        $ExistingContact = $CurrentContacts | Where-Object { $_.DisplayName -eq $Template.displayName }

                        # Update MailContact properties (email address)
                        $UpdateMailContactParams = @{
                            Identity             = $ExistingContact.Identity
                            ExternalEmailAddress = $Template.email
                        }

                        # Update the existing mail contact
                        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailContact' -cmdParams $UpdateMailContactParams -UseSystemMailbox $true

                        # Update Contact properties (names) if provided
                        $UpdateContactParams = @{
                            Identity = $ExistingContact.Identity
                        }
                        $ContactNeedsUpdate = $false

                        if (![string]::IsNullOrWhiteSpace($Template.firstName)) {
                            $UpdateContactParams.FirstName = $Template.firstName
                            $ContactNeedsUpdate = $true
                        }
                        if (![string]::IsNullOrWhiteSpace($Template.lastName)) {
                            $UpdateContactParams.LastName = $Template.lastName
                            $ContactNeedsUpdate = $true
                        }

                        # Only update Contact if we have name changes
                        if ($ContactNeedsUpdate) {
                            $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Contact' -cmdParams $UpdateContactParams -UseSystemMailbox $true
                        }

                        # Store contact info for second pass
                        $ProcessedContacts.Add([PSCustomObject]@{
                                Contact       = $Contact
                                ContactObject = $ExistingContact
                                Template      = $Template
                                IsNew         = $false
                            })
                    } catch {
                        $ProcessingFailures++
                        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                        Write-LogMessage -API $APIName -tenant $tenant -message "Failed to update contact $($Template.displayName): $ErrorMessage" -sev 'Error'
                    }
                }

                # Log processing summary
                $ProcessedCount = $ProcessedContacts.Count
                if ($ProcessedCount -gt 0) {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: Successfully processed $ProcessedCount contacts" -sev Info

                    # Wait for contacts to propagate before updating additional fields (only needed for small batches)
                    if ($ProcessedCount -le 3) {
                        Start-Sleep -Seconds 1
                    }

                    # Second pass: Update contacts with additional fields (only if needed)
                    $UpdateFailures = 0
                    $ContactsRequiringUpdates = 0

                    foreach ($ProcessedContactInfo in $ProcessedContacts) {
                        try {
                            $Template = $ProcessedContactInfo.Template
                            $ContactObject = $ProcessedContactInfo.ContactObject
                            $HasUpdates = $false

                            # Check if Set-Contact is needed
                            $ContactIdentity = if ($ProcessedContactInfo.IsNew) { $ContactObject.id } else { $ContactObject.Identity }
                            $SetContactParams = @{ Identity = $ContactIdentity }
                            $PropertyMap = @{
                                'Company'         = $Template.companyName
                                'StateOrProvince' = $Template.state
                                'StreetAddress'   = $Template.streetAddress
                                'Phone'           = $Template.businessPhone
                                'WebPage'         = $Template.website
                                'Title'           = $Template.jobTitle
                                'City'            = $Template.city
                                'PostalCode'      = $Template.postalCode
                                'CountryOrRegion' = $Template.country
                                'MobilePhone'     = $Template.mobilePhone
                            }

                            foreach ($Property in $PropertyMap.GetEnumerator()) {
                                if (![string]::IsNullOrWhiteSpace($Property.Value)) {
                                    $SetContactParams[$Property.Key] = $Property.Value
                                    $HasUpdates = $true
                                }
                            }

                            # Check if Set-MailContact is needed for additional properties
                            $MailContactParams = @{ Identity = $ContactIdentity }
                            $NeedsMailContactUpdate = $false

                            if ([bool]$Template.hidefromGAL) {
                                $MailContactParams.HiddenFromAddressListsEnabled = $true
                                $NeedsMailContactUpdate = $true
                                $HasUpdates = $true
                            }

                            if (![string]::IsNullOrWhiteSpace($Template.mailTip)) {
                                $MailContactParams.MailTip = $Template.mailTip
                                $NeedsMailContactUpdate = $true
                                $HasUpdates = $true
                            }

                            # Only increment and update if there are actual changes
                            if ($HasUpdates) {
                                $ContactsRequiringUpdates++

                                # Apply Set-Contact updates if needed
                                if ($SetContactParams.Count -gt 1) {
                                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Contact' -cmdParams $SetContactParams -UseSystemMailbox $true
                                }

                                # Apply Set-MailContact updates if needed
                                if ($NeedsMailContactUpdate) {
                                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailContact' -cmdParams $MailContactParams -UseSystemMailbox $true
                                }
                            }
                        } catch {
                            $UpdateFailures++
                            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                            Write-LogMessage -API $APIName -tenant $tenant -message "Failed to update additional fields for contact $($Template.displayName): $ErrorMessage" -sev 'Error'
                        }
                    }

                    # Log update summary only if updates were needed
                    if ($ContactsRequiringUpdates -gt 0) {
                        $SuccessfulUpdates = $ContactsRequiringUpdates - $UpdateFailures
                        Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: Updated additional fields for $SuccessfulUpdates of $ContactsRequiringUpdates contacts" -sev Info
                    }
                }

                # Final summary
                if ($ProcessingFailures -gt 0) {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: $ProcessingFailures contacts failed to process" -sev Error
                }
            }
        }

        if ($AlertEnabled) {
            $MissingContacts = ($CompareList | Where-Object { $_.missing }).Count
            $ContactsNeedingUpdate = ($CompareList | Where-Object { -not $_.missing -and -not $_.StateIsCorrect }).Count

            if ($MissingContacts -gt 0 -or $ContactsNeedingUpdate -gt 0) {
                foreach ($Contact in $CompareList | Where-Object { -not $_.StateIsCorrect }) {
                    if ($Contact.missing) {
                        $CurrentInfo = $Contact.Template | Select-Object -Property displayName, email, missing
                        Write-StandardsAlert -message "Mail contact $($Contact.Template.displayName) from template $($Contact.TemplateGUID) is missing." -object $CurrentInfo -tenant $Tenant -standardName 'DeployContactTemplates'
                    } else {
                        $CurrentInfo = $CurrentContacts | Where-Object -Property DisplayName -EQ $Contact.Template.displayName | Select-Object -Property DisplayName, ExternalEmailAddress, FirstName, LastName
                        $DiffList = ($Contact.Differences -join ', ')
                        Write-StandardsAlert -message "Mail contact $($Contact.Template.displayName) from template $($Contact.TemplateGUID) does not match template (differences: $DiffList)." -object $CurrentInfo -tenant $Tenant -standardName 'DeployContactTemplates'
                    }
                }
                Write-LogMessage -API $APIName -tenant $Tenant -message "DeployContactTemplate: $MissingContacts missing, $ContactsNeedingUpdate to update" -sev Info
            } else {
                Write-LogMessage -API $APIName -tenant $Tenant -message 'DeployContactTemplate: No contacts need processing' -sev Info
            }
        }

        if ($ReportEnabled) {
            $ExpectedValue = [PSCustomObject]@{
                state = 'Correctly configured'
            }
            $AllCorrect = -not ($CompareList | Where-Object { -not $_.StateIsCorrect })
            $CurrentValue = if ($AllCorrect) {
                [PSCustomObject]@{ state = 'Correctly configured' }
            } else {
                [PSCustomObject]@{
                    MissingContacts  = @($CompareList | Where-Object { $_.missing } | ForEach-Object {
                            $_.Template | Select-Object -Property displayName, Email
                        })
                    ContactsToUpdate = @($CompareList | Where-Object { -not $_.missing -and -not $_.StateIsCorrect } | ForEach-Object {
                            [PSCustomObject]@{
                                displayName = $_.Template.displayName
                                Email       = $_.Template.email
                                Differences = $_.Differences
                            }
                        })
                }
            }
            Set-CIPPStandardsCompareField -FieldName 'standards.DeployContactTemplates' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API $APIName -tenant $tenant -message "Failed to create or update mail contact(s) from templates, Error: $ErrorMessage" -sev 'Error'
    }
}

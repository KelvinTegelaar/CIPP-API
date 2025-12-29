Function Invoke-DeployContactTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Contact.ReadWrite
    .DESCRIPTION
        This function deploys contact(s) from template(s) to selected tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    try {
        $RequestBody = $Request.Body

        # Extract tenant IDs from the selectedTenants objects - get the value property
        $SelectedTenants = [System.Collections.Generic.List[string]]::new()

        foreach ($TenantItem in $RequestBody.selectedTenants) {
            if ($TenantItem.value) {
                $SelectedTenants.Add($TenantItem.value)
            } else {
                Write-LogMessage -headers $Headers -API $APIName -message "Tenant item missing value property: $($TenantItem | ConvertTo-Json -Compress)" -Sev 'Warning'
            }
        }

        # Handle AllTenants selection
        if ('AllTenants' -in $SelectedTenants) {
            $SelectedTenants = [System.Collections.Generic.List[string]]::new()
            $AllTenantsList = (Get-Tenants).defaultDomainName
            foreach ($Tenant in $AllTenantsList) {
                $SelectedTenants.Add($Tenant)
            }
        }

        # Get the contact templates from TemplateList
        $ContactTemplates = [System.Collections.Generic.List[object]]::new()

        if ($RequestBody.TemplateList -and $RequestBody.TemplateList.Count -gt 0) {
            # Templates are provided in TemplateList format
            foreach ($TemplateItem in $RequestBody.TemplateList) {
                if ($TemplateItem.value) {
                    $ContactTemplates.Add($TemplateItem.value)
                } else {
                    Write-LogMessage -headers $Headers -API $APIName -message "Template item missing value property: $($TemplateItem | ConvertTo-Json -Compress)" -Sev 'Warning'
                }
            }
        } else {
            throw "TemplateList is required and must contain at least one template"
        }

        if ($ContactTemplates.Count -eq 0) {
            throw "No valid contact templates found to deploy"
        }

        $Results = foreach ($TenantFilter in $SelectedTenants) {
            foreach ($ContactTemplate in $ContactTemplates) {
                try {
                    # Check if contact with this email already exists
                    $ExistingContactsParam = @{
                        tenantid         = $TenantFilter
                        cmdlet           = 'Get-MailContact'
                        cmdParams        = @{
                            Filter = "ExternalEmailAddress -eq '$($ContactTemplate.email)'"
                        }
                        useSystemMailbox = $true
                    }

                    $ExistingContacts = New-ExoRequest @ExistingContactsParam
                    $ContactExists = $ExistingContacts | Where-Object { $_.ExternalEmailAddress -eq $ContactTemplate.email }

                    if ($ContactExists) {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Contact with email '$($ContactTemplate.email)' already exists in tenant $TenantFilter" -Sev 'Warning'
                        "Contact '$($ContactTemplate.displayName)' with email '$($ContactTemplate.email)' already exists in tenant $TenantFilter"
                        continue
                    }

                    # Prepare the body for New-MailContact cmdlet
                    $BodyToship = @{
                        displayName          = $ContactTemplate.displayName
                        name                 = $ContactTemplate.displayName
                        ExternalEmailAddress = $ContactTemplate.email
                        FirstName            = $ContactTemplate.firstName
                        LastName             = $ContactTemplate.lastName
                    }

                    # Create the mail contact first
                    $NewContact = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-MailContact' -cmdParams $BodyToship -UseSystemMailbox $true

                    # Build SetContactParams efficiently with only provided values
                    $SetContactParams = @{
                        Identity = $NewContact.id
                    }

                    # Helper to add non-empty values
                    $PropertyMap = @{
                        'Title'           = $ContactTemplate.jobTitle
                        'Company'         = $ContactTemplate.companyName
                        'StreetAddress'   = $ContactTemplate.streetAddress
                        'City'            = $ContactTemplate.city
                        'StateOrProvince' = $ContactTemplate.state
                        'PostalCode'      = $ContactTemplate.postalCode
                        'CountryOrRegion' = $ContactTemplate.country
                        'Phone'           = $ContactTemplate.businessPhone
                        'MobilePhone'     = $ContactTemplate.mobilePhone
                        'WebPage'         = $ContactTemplate.website
                    }

                    # Add only non-null/non-empty properties
                    foreach ($Property in $PropertyMap.GetEnumerator()) {
                        if (![string]::IsNullOrWhiteSpace($Property.Value)) {
                            $SetContactParams[$Property.Key] = $Property.Value
                        }
                    }

                    # Update the contact with additional details only if we have properties to set
                    if ($SetContactParams.Count -gt 1) {
                        Start-Sleep -Milliseconds 500 # Ensure the contact is created before updating
                        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Contact' -cmdParams $SetContactParams -UseSystemMailbox $true
                    }

                    # Check if we need to update MailContact properties
                    $needsMailContactUpdate = $false
                    $MailContactParams = @{
                        Identity = $NewContact.id
                    }

                    # Only add HiddenFromAddressListsEnabled if we're actually hiding from GAL
                    if ([bool]$ContactTemplate.hidefromGAL) {
                        $MailContactParams.HiddenFromAddressListsEnabled = $true
                        $needsMailContactUpdate = $true
                    }

                    # Add MailTip if provided
                    if (![string]::IsNullOrWhiteSpace($ContactTemplate.mailTip)) {
                        $MailContactParams.MailTip = $ContactTemplate.mailTip
                        $needsMailContactUpdate = $true
                    }

                    # Only call Set-MailContact if we have changes to make
                    if ($needsMailContactUpdate) {
                        Start-Sleep -Milliseconds 500 # Ensure the contact is created before updating
                        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailContact' -cmdParams $MailContactParams -UseSystemMailbox $true
                    }

                    # Log the result
                    $ContactResult = "Successfully created contact '$($ContactTemplate.displayName)' with email '$($ContactTemplate.email)'"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ContactResult -Sev 'Info'

                    # Return success message as a simple string
                    "Successfully deployed contact '$($ContactTemplate.displayName)' to tenant $TenantFilter"
                }
                catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $ErrorDetail = "Failed to deploy contact '$($ContactTemplate.displayName)' to tenant $TenantFilter. Error: $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ErrorDetail -Sev 'Error'

                    # Return error message as a simple string
                    "Failed to deploy contact '$($ContactTemplate.displayName)' to tenant $TenantFilter. Error: $($ErrorMessage.NormalizedError)"
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to process contact template deployment request. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Results}
        })
}

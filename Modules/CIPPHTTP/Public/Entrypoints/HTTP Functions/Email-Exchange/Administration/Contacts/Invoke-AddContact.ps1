function Invoke-AddContact {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Contact.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $ContactObject = $Request.Body
    $TenantId = $ContactObject.tenantid

    try {
        # Prepare the body for New-MailContact cmdlet
        $BodyToship = @{
            displayName          = $ContactObject.displayName
            name                 = $ContactObject.displayName
            ExternalEmailAddress = $ContactObject.email
            FirstName            = $ContactObject.firstName
            LastName             = $ContactObject.lastName
        }

        # Create the mail contact first
        $NewContact = New-ExoRequest -tenantid $TenantId -cmdlet 'New-MailContact' -cmdParams $BodyToship -UseSystemMailbox $true

        # Build SetContactParams efficiently with only provided values
        $SetContactParams = @{
            Identity = $NewContact.id
        }

        # Helper to add non-empty values
        $PropertyMap = @{
            'Title'           = $ContactObject.Title
            'Company'         = $ContactObject.Company
            'StreetAddress'   = $ContactObject.StreetAddress
            'City'            = $ContactObject.City
            'StateOrProvince' = $ContactObject.State
            'PostalCode'      = $ContactObject.PostalCode
            'CountryOrRegion' = $ContactObject.CountryOrRegion
            'Phone'           = $ContactObject.phone
            'MobilePhone'     = $ContactObject.mobilePhone
            'WebPage'         = $ContactObject.website
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
            $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-Contact' -cmdParams $SetContactParams -UseSystemMailbox $true
        }

        # Check if we need to update MailContact properties
        $needsMailContactUpdate = $false
        $MailContactParams = @{
            Identity = $NewContact.id
        }

        # Only add HiddenFromAddressListsEnabled if we're actually hiding from GAL
        if ([bool]$ContactObject.hidefromGAL) {
            $MailContactParams.HiddenFromAddressListsEnabled = $true
            $needsMailContactUpdate = $true
        }

        # Add MailTip if provided
        if (![string]::IsNullOrWhiteSpace($ContactObject.mailTip)) {
            $MailContactParams.MailTip = $ContactObject.mailTip
            $needsMailContactUpdate = $true
        }

        # Only call Set-MailContact if we have changes to make
        if ($needsMailContactUpdate) {
            Start-Sleep -Milliseconds 500 # Ensure the contact is created before updating
            $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-MailContact' -cmdParams $MailContactParams -UseSystemMailbox $true
        }

        # Log the result
        $Result = "Successfully created contact $($ContactObject.displayName) with email address $($ContactObject.email)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create contact. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError

    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}

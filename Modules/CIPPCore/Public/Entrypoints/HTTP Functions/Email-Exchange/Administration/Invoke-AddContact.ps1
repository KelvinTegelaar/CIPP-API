using namespace System.Net

Function Invoke-AddContact {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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
            $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-Contact' -cmdParams $SetContactParams -UseSystemMailbox $true
        }

        # Build MailContact parameters efficiently
        $MailContactParams = @{
            Identity = $NewContact.id
            HiddenFromAddressListsEnabled = [bool]$ContactObject.hidefromGAL
        }

        # Add MailTip if provided
        if (![string]::IsNullOrWhiteSpace($ContactObject.mailTip)) {
            $MailContactParams.MailTip = $ContactObject.mailTip
        }

        $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-MailContact' -cmdParams $MailContactParams -UseSystemMailbox $true

        # Log the result
        $Result = "Successfully created contact $($ContactObject.displayName) with email address $($ContactObject.email)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create contact. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError

    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{Results = $Result }
    })
}

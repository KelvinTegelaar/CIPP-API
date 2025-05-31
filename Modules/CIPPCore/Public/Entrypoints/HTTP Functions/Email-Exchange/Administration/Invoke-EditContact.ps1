using namespace System.Net

Function Invoke-EditContact {
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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantID = $Request.Body.tenantID

    try {
        # Extract contact information from the request body
        $contactInfo = $Request.Body

        # Build contact parameters with only provided values
        $bodyForSetContact = @{
            Identity = $contactInfo.ContactID
        }

        # Map of properties to check and add
        $ContactPropertyMap = @{
            'DisplayName'         = $contactInfo.displayName
            'WindowsEmailAddress' = $contactInfo.email
            'FirstName'           = $contactInfo.firstName
            'LastName'            = $contactInfo.LastName
            'Title'               = $contactInfo.Title
            'StreetAddress'       = $contactInfo.StreetAddress
            'PostalCode'          = $contactInfo.PostalCode
            'City'                = $contactInfo.City
            'StateOrProvince'     = $contactInfo.State
            'CountryOrRegion'     = $contactInfo.CountryOrRegion
            'Company'             = $contactInfo.Company
            'MobilePhone'         = $contactInfo.mobilePhone
            'Phone'               = $contactInfo.phone
            'WebPage'             = $contactInfo.website
        }

        # Add only non-null/non-empty properties
        foreach ($Property in $ContactPropertyMap.GetEnumerator()) {
            if (![string]::IsNullOrWhiteSpace($Property.Value)) {
                $bodyForSetContact[$Property.Key] = $Property.Value
            }
        }

        # Update contact only if we have properties to set beyond Identity
        if ($bodyForSetContact.Count -gt 1) {
            $null = New-ExoRequest -tenantid $TenantID -cmdlet 'Set-Contact' -cmdParams $bodyForSetContact -UseSystemMailbox $true
        }

        # Prepare mail contact specific parameters
        $MailContactParams = @{
            Identity = $contactInfo.ContactID
        }

        # Handle boolean conversion safely
        if ($null -ne $contactInfo.hidefromGAL) {
            $MailContactParams.HiddenFromAddressListsEnabled = [bool]$contactInfo.hidefromGAL
        }

        # Add MailTip if provided
        if (![string]::IsNullOrWhiteSpace($contactInfo.mailTip)) {
            $MailContactParams.MailTip = $contactInfo.mailTip
        }

        # Update mail contact only if we have properties to set beyond Identity
        if ($MailContactParams.Count -gt 1) {
            $null = New-ExoRequest -tenantid $TenantID -cmdlet 'Set-MailContact' -cmdParams $MailContactParams -UseSystemMailbox $true
        }

        $Results = "Successfully edited contact $($contactInfo.displayName)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantID -message $Results -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to edit contact. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantID -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{Results = $Results }
    })
}

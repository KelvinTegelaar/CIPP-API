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

        # Log the received contact object
        Write-Host "Received contact object: $($contactInfo | ConvertTo-Json)"

        # Prepare the body for the Set-Contact cmdlet
        $bodyForSetContact = [pscustomobject] @{
            'Identity'            = $contactInfo.ContactID
            'DisplayName'         = $contactInfo.displayName
            'WindowsEmailAddress' = $contactInfo.email
            'FirstName'           = $contactInfo.firstName
            'LastName'            = $contactInfo.LastName
            'Title'               = $contactInfo.Title
            'StreetAddress'       = $contactInfo.StreetAddress
            'PostalCode'          = $contactInfo.PostalCode
            'City'                = $contactInfo.City
            'CountryOrRegion'     = $contactInfo.CountryOrRegion
            'Company'             = $contactInfo.Company
            'mobilePhone'         = $contactInfo.mobilePhone
            'phone'               = $contactInfo.phone
        }

        # Call the Set-Contact cmdlet to update the contact
        $null = New-ExoRequest -tenantid $TenantID -cmdlet 'Set-Contact' -cmdParams $bodyForSetContact -UseSystemMailbox $true
        $null = New-ExoRequest -tenantid $TenantID -cmdlet 'Set-MailContact' -cmdParams @{Identity = $contactInfo.ContactID; HiddenFromAddressListsEnabled = [System.Convert]::ToBoolean($contactInfo.hidefromGAL) } -UseSystemMailbox $true
        $Results = "Successfully edited contact $($contactInfo.DisplayName)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantID -message $Results -Sev Info
        $StatusCode = [HttpStatusCode]::OK

    } catch {
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

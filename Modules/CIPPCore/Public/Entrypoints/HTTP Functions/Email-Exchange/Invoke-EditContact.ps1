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

    $APIName = $TriggerMetadata.FunctionName
    $TenantID = $Request.body.tenantID
    $ExecutingUser = $Request.headers.'x-ms-client-principal'
    Write-LogMessage -user $ExecutingUser -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        # Extract contact information from the request body
        $contactInfo = $Request.body

        # Log the received contact object
        Write-Host "Received contact object: $($contactInfo | ConvertTo-Json)"

        # Prepare the body for the Set-Contact cmdlet
        $bodyForSetContact = [pscustomobject] @{
            'DisplayName'         = $contactInfo.DisplayName
            'WindowsEmailAddress' = $contactInfo.mail
            'FirstName'           = $contactInfo.firstName
            'LastName'            = $contactInfo.LastName
            'Title'               = $contactInfo.jobTitle
            'StreetAddress'       = $contactInfo.StreetAddress
            'PostalCode'          = $contactInfo.PostalCode
            'City'                = $contactInfo.City
            'CountryOrRegion'     = $contactInfo.Country
            'Company'             = $contactInfo.companyName
            'mobilePhone'         = $contactInfo.MobilePhone
            'phone'               = $contactInfo.BusinessPhone
            'identity'            = $contactInfo.ContactID
        }

        # Call the Set-Contact cmdlet to update the contact
        $null = New-ExoRequest -tenantid $TenantID -cmdlet 'Set-Contact' -cmdParams $bodyForSetContact -UseSystemMailbox $true
        $Results = "Successfully edited contact $($contactInfo.DisplayName)"
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $TenantID -message $Results -Sev Info
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to edit contact. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $TenantID -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    $Results = [pscustomobject]@{'Results' = "$Results" }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $responseResults
        })
}

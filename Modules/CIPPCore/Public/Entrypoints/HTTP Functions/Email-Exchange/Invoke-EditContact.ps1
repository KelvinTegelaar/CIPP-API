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
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $contactobj = $Request.body
    write-host "This is the contact object: $contactobj"
    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    try {

        $BodyToship = [pscustomobject] @{
            'DisplayName'           = $contactobj.DisplayName
            'WindowsEmailAddress'   = $contactobj.mail
            'FirstName'             = $contactObj.firstName
            'LastName'              = $contactobj.LastName
            "Title"                 = $contactobj.jobTitle
            "StreetAddress"         = $contactobj.StreetAddress
            "PostalCode"            = $contactobj.PostalCode
            "City"                  = $contactobj.City
            "CountryOrRegion"       = $contactobj.Country
            "Company"               = $contactobj.companyName
            "mobilePhone"           = $contactobj.MobilePhone
            "phone"                 = $contactobj.BusinessPhone
            'identity'              = $contactobj.ContactID
        }
        $EditContact = New-ExoRequest -tenantid $Request.body.tenantID -cmdlet 'Set-Contact' -cmdparams $BodyToship -UseSystemMailbox $true
        $Results = [pscustomobject]@{'Results' = "Successfully edited contact $($contactobj.Displayname)" }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($contactobj.tenantid) -message "Created contact $($contactobj.displayname)" -Sev 'Info'

    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($contactobj.tenantid) -message "Contact creation API failed. $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{'Results' = "Failed to edit contact. $($_.Exception.Message)" }

    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}

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
        $BodyToship = [pscustomobject] @{
            displayName          = $ContactObject.displayName
            name                 = $ContactObject.displayName
            ExternalEmailAddress = $ContactObject.email
            FirstName            = $ContactObject.firstName
            LastName             = $ContactObject.lastName
        }

        # Create the mail contact first
        $NewContact = New-ExoRequest -tenantid $TenantId -cmdlet 'New-MailContact' -cmdParams $BodyToship -UseSystemMailbox $true

        # Prepare the body for Set-Contact cmdlet to add additional details
        $SetContactParams = [pscustomobject] @{
            Identity = $NewContact.id
        }

        # Add optional fields if they exist
        if ($ContactObject.Title) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'Title' -Value $ContactObject.Title }
        if ($ContactObject.Company) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'Company' -Value $ContactObject.Company }
        if ($ContactObject.StreetAddress) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'StreetAddress' -Value $ContactObject.StreetAddress }
        if ($ContactObject.City) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'City' -Value $ContactObject.City }
        if ($ContactObject.State) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'StateOrProvince' -Value $ContactObject.State }
        if ($ContactObject.PostalCode) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'PostalCode' -Value $ContactObject.PostalCode }
        if ($ContactObject.CountryOrRegion) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'CountryOrRegion' -Value $ContactObject.CountryOrRegion }
        if ($ContactObject.phone) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'Phone' -Value $ContactObject.phone }
        if ($ContactObject.mobilePhone) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'MobilePhone' -Value $ContactObject.mobilePhone }
        if ($ContactObject.website) { $SetContactParams | Add-Member -MemberType NoteProperty -Name 'WebPage' -Value $ContactObject.website }

        # Update the contact with additional details
        $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-Contact' -cmdParams $SetContactParams -UseSystemMailbox $true

        # Set mail contact specific properties
        $MailContactParams = @{
            Identity = $NewContact.id
            HiddenFromAddressListsEnabled = [boolean]$ContactObject.hidefromGAL
        }

        # Add MailTip if provided
        if ($ContactObject.mailTip) {
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

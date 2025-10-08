using namespace System.Collections.Generic
using namespace System.Text.RegularExpressions

Function Invoke-ListContacts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Contact.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Get query parameters
    $TenantFilter = $Request.Query.tenantFilter
    $ContactID = $Request.Query.id

    # Early validation and exit
    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = 'tenantFilter is required'
        })
        return
    }

    # Pre-compiled regex for MailTip cleaning
    $script:HtmlTagRegex ??= [regex]::new('<[^>]+>', [RegexOptions]::Compiled)
    $script:LineBreakRegex ??= [regex]::new('\\n|\r\n|\r', [RegexOptions]::Compiled)
    $script:SmtpPrefixRegex ??= [regex]::new('^SMTP:', [RegexOptions]::Compiled -bor [RegexOptions]::IgnoreCase)

    function ConvertTo-ContactObject {
        param($Contact, $MailContact)

        # Early exit if essential data missing
        if (!$Contact.Id) { return $null }

        $mailAddress = if ($MailContact.ExternalEmailAddress) {
            $script:SmtpPrefixRegex.Replace($MailContact.ExternalEmailAddress, [string]::Empty, 1)
        } else { $null }

        $cleanMailTip = if ($MailContact.MailTip -and $MailContact.MailTip.Length -gt 0) {
            $cleaned = $script:HtmlTagRegex.Replace($MailContact.MailTip, [string]::Empty)
            $cleaned = $script:LineBreakRegex.Replace($cleaned, "`n")
            $cleaned.Trim()
        } else { $null }

        $phoneCapacity = 0
        if ($Contact.Phone) { $phoneCapacity++ }
        if ($Contact.MobilePhone) { $phoneCapacity++ }

        $phones = if ($phoneCapacity -gt 0) {
            $phoneList = [List[hashtable]]::new($phoneCapacity)
            if ($Contact.Phone) {
                $phoneList.Add(@{ type = "business"; number = $Contact.Phone })
            }
            if ($Contact.MobilePhone) {
                $phoneList.Add(@{ type = "mobile"; number = $Contact.MobilePhone })
            }
            $phoneList.ToArray()
        } else { @() }

        return @{
            id = $Contact.Id
            displayName = $Contact.DisplayName
            givenName = $Contact.FirstName
            surname = $Contact.LastName
            mail = $mailAddress
            companyName = $Contact.Company
            jobTitle = $Contact.Title
            website = $Contact.WebPage
            notes = $Contact.Notes
            hidefromGAL = $MailContact.HiddenFromAddressListsEnabled
            mailTip = $cleanMailTip
            onPremisesSyncEnabled = $Contact.IsDirSynced
            addresses = @(@{
                street = $Contact.StreetAddress
                city = $Contact.City
                state = $Contact.StateOrProvince
                countryOrRegion = $Contact.CountryOrRegion
                postalCode = $Contact.PostalCode
            })
            phones = $phones
        }
    }

    try {
        if (![string]::IsNullOrWhiteSpace($ContactID)) {
            # Single contact request - keep existing complex formatting
            Write-Host "Getting specific contact: $ContactID"

            $Contact = New-EXORequest -tenantid $TenantFilter -cmdlet 'Get-Contact' -cmdParams @{
                Identity = $ContactID
            }

            $MailContact = New-EXORequest -tenantid $TenantFilter -cmdlet 'Get-MailContact' -cmdParams @{
                Identity = $ContactID
            }

            if (!$Contact -or !$MailContact) {
                throw "Contact not found or insufficient permissions"
            }

            $ContactResponse = ConvertTo-ContactObject -Contact $Contact -MailContact $MailContact

        } else {
            # Get all contacts - simplified approach
            Write-Host "Getting all contacts"

            $ContactResponse = New-EXORequest -tenantid $TenantFilter -cmdlet 'Get-Contact' -cmdParams @{
                Filter = "RecipientTypeDetails -eq 'MailContact'"
                ResultSize = 'Unlimited'
            } | Select-Object -Property City, Company, Department, DisplayName, FirstName, LastName, IsDirSynced, Guid, WindowsEmailAddress

            # Return empty array if no contacts found
            if (!$ContactResponse) {
                $ContactResponse = @()
            }
        }

        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ContactResponse = $ErrorMessage
        Write-Host "Error in ListContacts: $ErrorMessage"
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $ContactResponse
    })
}

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

        $BodyToship = [pscustomobject] @{
            displayName          = $ContactObject.displayName
            name                 = $ContactObject.displayName
            ExternalEmailAddress = $ContactObject.email
            FirstName            = $ContactObject.firstName
            LastName             = $ContactObject.lastName

        }
        # Create the contact
        $NewContact = New-ExoRequest -tenantid $TenantId -cmdlet 'New-MailContact' -cmdParams $BodyToship -UseSystemMailbox $true
        $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-MailContact' -cmdParams @{Identity = $NewContact.id; HiddenFromAddressListsEnabled = [boolean]$ContactObject.hidefromGAL } -UseSystemMailbox $true

        # Log the result
        $Result = "Created contact $($ContactObject.displayName) with email address $($ContactObject.email)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
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

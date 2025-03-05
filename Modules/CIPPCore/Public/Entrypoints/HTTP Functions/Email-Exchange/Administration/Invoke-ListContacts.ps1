using namespace System.Net

Function Invoke-ListContacts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Contact.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    # Define fields to retrieve
    $selectList = @(
        'id',
        'companyName',
        'displayName',
        'mail',
        'onPremisesSyncEnabled',
        'editURL',
        'givenName',
        'jobTitle',
        'surname',
        'addresses',
        'phones'
    )

    # Get query parameters
    $TenantFilter = $Request.Query.tenantFilter
    $ContactID = $Request.Query.id

    # Validate required parameters
    if (-not $TenantFilter) {
        $StatusCode = [HttpStatusCode]::BadRequest
        $GraphRequest = 'tenantFilter is required'
        Write-Host 'Error: Missing tenantFilter parameter'
    } else {
        try {
            # Construct Graph API URI based on whether an ID is provided
            $graphUri = if ([string]::IsNullOrWhiteSpace($ContactID) -eq $false) {
                "https://graph.microsoft.com/beta/contacts/$($ContactID)?`$select=$($selectList -join ',')"
            } else {
                "https://graph.microsoft.com/beta/contacts?`$top=999&`$select=$($selectList -join ',')"
            }

            # Make the Graph API request
            $GraphRequest = New-GraphGetRequest -uri $graphUri -tenantid $TenantFilter

            if ([string]::IsNullOrWhiteSpace($ContactID) -eq $false) {
                $HiddenFromGAL = New-EXORequest -tenantid $TenantFilter -cmdlet 'Get-Recipient' -cmdParams @{RecipientTypeDetails = 'MailContact' } -Select 'HiddenFromAddressListsEnabled,ExternalDirectoryObjectId' | Where-Object { $_.ExternalDirectoryObjectId -eq $ContactID }
                $GraphRequest | Add-Member -NotePropertyName 'hidefromGAL' -NotePropertyValue $HiddenFromGAL.HiddenFromAddressListsEnabled
            }
            # Ensure single result when ID is provided
            if ($ContactID -and $GraphRequest -is [array]) {
                $GraphRequest = $GraphRequest | Select-Object -First 1
            }
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $ErrorMessage
        }
    }

    # Return response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Where-Object { $null -ne $_.id })
        })
}

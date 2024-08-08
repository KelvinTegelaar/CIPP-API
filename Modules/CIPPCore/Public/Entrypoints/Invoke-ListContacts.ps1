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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $selectlist = 'id', 'companyName', 'displayName', 'mail', 'onPremisesSyncEnabled', 'editURL', "givenName", "jobTitle", "surname", "addresses", "phones"

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $ContactID = $Request.Query.ContactID

    Write-Host "Tenant Filter: $TenantFilter"
    Write-Host "This is the Contact ID: $ContactID"
    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contacts/$($ContactID)?`$top=999&`$select=$($selectlist -join ',')" -tenantid $TenantFilter | Select-Object $selectlist | ForEach-Object {
            $_.editURL = "https://outlook.office365.com/ecp/@$TenantFilter/UsersGroups/EditContact.aspx?exsvurl=1&realm=$($env:TenantID)&mkt=en-US&id=$($_.id)"
            $_
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Where-Object -Property id -NE $null)
        })

}

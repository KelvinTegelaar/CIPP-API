using namespace System.Net

Function Invoke-ListDeletedItems {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $selectlist = 'id', 'accountEnabled', 'businessPhones', 'city', 'createdDateTime', 'companyName', 'country', 'department', 'displayName', 'faxNumber', 'givenName', 'isResourceAccount', 'jobTitle', 'mail', 'mailNickname', 'mobilePhone', 'onPremisesDistinguishedName', 'officeLocation', 'onPremisesLastSyncDateTime', 'otherMails', 'postalCode', 'preferredDataLocation', 'preferredLanguage', 'proxyAddresses', 'showInAddressList', 'state', 'streetAddress', 'surname', 'usageLocation', 'userPrincipalName', 'userType', 'assignedLicenses', 'onPremisesSyncEnabled', 'LicJoined', 'Aliases', 'primDomain'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $Types = 'Application', 'User', 'Device', 'Group'
    $GraphRequest = foreach ($Type in $Types) {
    (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/microsoft.graph.$($Type)" -tenantid $TenantFilter) | Where-Object -Property '@odata.context' -NotLike '*graph.microsoft.com*' | Select-Object *, @{ Name = 'TargetType'; Expression = { $Type } }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}

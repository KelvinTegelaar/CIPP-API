using namespace System.Net

Function Invoke-ListUserGroups {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $UserID = $Request.Query.UserID


    $URI = "https://graph.microsoft.com/beta/users/$UserID/memberOf/$/microsoft.graph.group?`$select=id,displayName,mailEnabled,securityEnabled,groupTypes,onPremisesSyncEnabled,mail,isAssignableToRole`&$orderby=displayName asc" 
    Write-Host $URI
    $GraphRequest = New-GraphGetRequest -uri $URI -tenantid $TenantFilter -noPagination $true -verbose | Select-Object id,
    @{ Name = 'DisplayName'; Expression = { $_.displayName } },
    @{ Name = 'MailEnabled'; Expression = { $_.mailEnabled } },
    @{ Name = 'Mail'; Expression = { $_.mail } },
    @{ Name = 'SecurityGroup'; Expression = { $_.securityEnabled } },
    @{ Name = 'GroupTypes'; Expression = { $_.groupTypes -join ',' } },
    @{ Name = 'OnPremisesSync'; Expression = { $_.onPremisesSyncEnabled } },
    @{ Name = 'IsAssignableToRole'; Expression = { $_.isAssignableToRole } }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}

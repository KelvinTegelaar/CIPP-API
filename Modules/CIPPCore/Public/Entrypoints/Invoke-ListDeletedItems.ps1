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
    $TenantFilter = $Request.Query.tenantFilter
    $ExecutingUser = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $ExecutingUser -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Types = 'Application', 'User', 'Device', 'Group'
    $GraphRequest = foreach ($Type in $Types) {
    (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/microsoft.graph.$($Type)" -tenantid $TenantFilter) |
            Where-Object -Property '@odata.context' -NotLike '*graph.microsoft.com*' |
            Select-Object *, @{ Name = 'TargetType'; Expression = { $Type } }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })
}

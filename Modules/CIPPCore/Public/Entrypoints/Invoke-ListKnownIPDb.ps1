using namespace System.Net

Function Invoke-ListKnownIPDb {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Table = Get-CIPPTable -TableName 'knownlocationdb'
    $Filter = "Tenant eq '$($Request.Query.TenantFilter)'"
    $KnownIPDb = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($KnownIPDb)
        })

}

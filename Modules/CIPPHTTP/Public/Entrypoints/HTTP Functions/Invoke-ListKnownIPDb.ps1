Function Invoke-ListKnownIPDb {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter


    $Table = Get-CIPPTable -TableName 'knownlocationdbv2'
    $Filter = "Tenant eq '$($TenantFilter)'"
    $KnownIPDb = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($KnownIPDb)
        }

}

function Invoke-ListKnownIPDb {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists known IP address entries from the CIPP IP database, optionally filtered by tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    if (-not [string]::IsNullOrEmpty($TenantFilter)) {
        $TenantFilter = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    }


    $Table = Get-CIPPTable -TableName 'knownlocationdbv2'
    $Filter = "Tenant eq '$($TenantFilter)'"
    $KnownIPDb = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($KnownIPDb)
    }

}

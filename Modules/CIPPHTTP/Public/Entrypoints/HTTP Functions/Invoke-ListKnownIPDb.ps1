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

    $Table = Get-CIPPTable -TableName 'knownlocationdbv2'
    $KnownIPDb = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ip'"

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($KnownIPDb)
    }

}

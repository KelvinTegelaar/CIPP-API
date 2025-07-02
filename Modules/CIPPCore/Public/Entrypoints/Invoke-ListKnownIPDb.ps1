using namespace System.Net

function Invoke-ListKnownIPDb {
    <#
    .SYNOPSIS
    List known IP addresses and locations from the database
    
    .DESCRIPTION
    Retrieves known IP addresses and location information from the knownlocationdbv2 table for a specific tenant
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Security
    Summary: List Known IP Database
    Description: Retrieves known IP addresses and location information from the knownlocationdbv2 table for a specific tenant for security and location tracking
    Tags: Security,IP Database,Location Tracking
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Response: Returns an array of known IP location objects from the knownlocationdbv2 table
    Response: Each object contains IP address and location information for the specified tenant
    Response: Example: [
      {
        "PartitionKey": "KnownLocations",
        "RowKey": "192.168.1.100",
        "Tenant": "contoso.onmicrosoft.com",
        "IPAddress": "192.168.1.100",
        "Location": "Office Building A",
        "Description": "Main office network",
        "LastSeen": "2024-01-15T10:30:00Z"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter


    $Table = Get-CIPPTable -TableName 'knownlocationdbv2'
    $Filter = "Tenant eq '$($TenantFilter)'"
    $KnownIPDb = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($KnownIPDb)
        })

}

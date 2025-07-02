using namespace System.Net

function Invoke-ListIPWhitelist {
    <#
    .SYNOPSIS
    List trusted IP addresses from CIPP storage
    
    .DESCRIPTION
    Retrieves the list of trusted IP addresses stored in the CIPP trustedIps table for access control and security
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Security
    Summary: List IP Whitelist
    Description: Retrieves the list of trusted IP addresses stored in the CIPP trustedIps table for access control and security management
    Tags: Security,IP Whitelist,Access Control
    Response: Returns an array of trusted IP objects from the trustedIps table
    Response: Each object contains IP address information and metadata
    Response: Example: [
      {
        "PartitionKey": "TrustedIPs",
        "RowKey": "192.168.1.100",
        "IPAddress": "192.168.1.100",
        "Description": "Office Network",
        "AddedBy": "admin@contoso.com",
        "AddedDate": "2024-01-15T10:30:00Z"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CippTable -tablename 'trustedIps'
    $body = Get-CIPPAzDataTableEntity @Table

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($body)
        })
}

using namespace System.Net

function Invoke-ListBreachesTenant {
    <#
    .SYNOPSIS
    List data breaches for a tenant from stored results
    
    .DESCRIPTION
    Retrieves stored breach data for a specific tenant or all tenants from the UserBreaches table
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Security
    Summary: List Breaches Tenant
    Description: Retrieves stored breach data for a specific tenant or all tenants from the UserBreaches table, returning previously executed breach search results
    Tags: Security,Breaches,Storage
    Parameter: tenantFilter (string) [query] - Target tenant identifier to retrieve breaches for (use 'AllTenants' for all tenants)
    Response: Returns an array of breach objects stored in the UserBreaches table
    Response: Each breach object contains information about compromised accounts and services
    Response: If no breaches are found, returns an empty array
    Example: [
      {
        "Name": "Adobe",
        "Title": "Adobe",
        "Domain": "adobe.com",
        "BreachDate": "2013-10-04",
        "PwnCount": 152445165,
        "Description": "In October 2013, 153 million Adobe accounts were breached...",
        "DataClasses": [
          "Email addresses",
          "Password hints",
          "Passwords",
          "Usernames"
        ]
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter

    $Table = Get-CIPPTable -TableName UserBreaches
    if ($TenantFilter -ne 'AllTenants') {
        $filter = "PartitionKey eq '$TenantFilter'"
    }
    else {
        $filter = $null
    }
    try {
        $usersResults = (Get-CIPPAzDataTableEntity @Table -Filter $filter).breaches | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    catch {
        $usersResults = $null
    }
    if ($null -eq $usersResults) {
        $usersResults = @()
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($usersResults)
        })

}

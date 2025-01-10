using namespace System.Net

Function Invoke-ListBreachesTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.query.TenantFilter
    $Table = Get-CIPPTable -TableName UserBreaches
    if ($TenantFilter -ne 'AllTenants') {
        $filter = "PartitionKey eq '$TenantFilter'"
    } else {
        $filter = $null
    }
    $usersResults = (Get-CIPPAzDataTableEntity @Table -Filter $filter).breaches | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($usersResults -eq $null) {
        $usersResults = @()
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($usersResults)
        })

}

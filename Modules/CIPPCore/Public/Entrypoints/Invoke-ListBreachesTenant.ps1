using namespace System.Net

function Invoke-ListBreachesTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $TenantFilter = $Request.Query.tenantFilter

    $Table = Get-CIPPTable -TableName UserBreaches
    if ($TenantFilter -ne 'AllTenants') {
        $filter = "PartitionKey eq '$TenantFilter'"
    } else {
        $filter = $null
    }
    try {
        $usersResults = (Get-CIPPAzDataTableEntity @Table -Filter $filter).breaches | ConvertFrom-Json -ErrorAction SilentlyContinue
    } catch {
        $usersResults = $null
    }
    if ($null -eq $usersResults) {
        $usersResults = @()
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($usersResults)
    }

}

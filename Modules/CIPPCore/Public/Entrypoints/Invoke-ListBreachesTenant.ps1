function Invoke-ListBreachesTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
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
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($usersResults)
    }

}

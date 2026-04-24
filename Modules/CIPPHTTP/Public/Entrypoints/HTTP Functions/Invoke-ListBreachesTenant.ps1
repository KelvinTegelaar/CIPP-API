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
        $Tenants = Get-Tenants -IncludeErrors
        $Rows = Get-CIPPAzDataTableEntity @Table -Filter $filter | Where-Object { $Tenants.defaultDomainName -contains $_.PartitionKey }
        $usersResults = $Rows.breaches | ConvertFrom-Json -ErrorAction SilentlyContinue
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

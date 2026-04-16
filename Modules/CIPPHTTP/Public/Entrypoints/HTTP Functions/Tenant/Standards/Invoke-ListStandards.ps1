Function Invoke-ListStandards {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter


    if ($Request.Query.ShowConsolidated -eq $true) {
        $StandardQuery = @{
            TenantFilter = $TenantFilter
        }
        if ($TenantFilter -eq 'AllTenants') {
            $StandardQuery.ListAllTenants = $true
        }
        $CurrentStandards = @(Get-CIPPStandards @StandardQuery)
    } else {
        $Table = Get-CippTable -tablename 'standards'
        $Filter = "PartitionKey eq 'standards'"

        try {
            if ($TenantFilter) {
                $Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 15 -ErrorAction Stop | Where-Object Tenant -EQ $TenantFilter
            } else {
                $Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 15 -ErrorAction Stop
            }
        } catch {}

        $CurrentStandards = foreach ($tenant in $Tenants) {
            [PSCustomObject]@{
                displayName     = $tenant.tenant
                appliedBy       = $tenant.addedBy
                appliedAt       = $tenant.appliedAt
                standards       = $tenant.Standards
                StandardsExport = ($tenant.Standards.PSObject.Properties.Name) -join ', '
            }
        }

        $CurrentStandards = ConvertTo-Json -InputObject @($CurrentStandards) -Depth 15 -Compress
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $CurrentStandards
        })

}

using namespace System.Net

Function Invoke-ListStandards {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    if ($Request.Query.ShowConsolidated -eq $true) {
        $StandardQuery = @{
            TenantFilter = $Request.Query.TenantFilter
        }
        if ($Request.Query.TenantFilter -eq 'AllTenants') {
            $StandardQuery.ListAllTenants = $true
        }
        $CurrentStandards = @(Get-CIPPStandards @StandardQuery)
    } else {
        $Table = Get-CippTable -tablename 'standards'
        $Filter = "PartitionKey eq 'standards'"

        try {
            if ($Request.query.TenantFilter) {
                $tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 15 -ErrorAction Stop | Where-Object Tenant -EQ $Request.query.tenantFilter
            } else {
                $Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 15 -ErrorAction Stop
            }
        } catch {}

        $CurrentStandards = foreach ($tenant in $tenants) {
            [PSCustomObject]@{
                displayName     = $tenant.tenant
                appliedBy       = $tenant.addedBy
                appliedAt       = $tenant.appliedAt
                standards       = $tenant.Standards
                StandardsExport = ($tenant.Standards.psobject.properties.name) -join ', '
            }
        }
        if (!$CurrentStandards) {
            $CurrentStandards = [PSCustomObject]@{
                displayName = 'No Standards applied'
                appliedBy   = $null
                appliedAt   = $null
                standards   = @{none = $null }
            }
        }

        $CurrentStandards = ConvertTo-Json -InputObject @($CurrentStandards) -Depth 15 -Compress
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $CurrentStandards
        })

}

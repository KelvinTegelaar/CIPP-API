function New-CIPPDbRequest {
    <#
    .SYNOPSIS
        Query the CIPP Reporting database by partition key

    .DESCRIPTION
        Retrieves data from the CippReportingDB table filtered by partition key (tenant)

    .PARAMETER TenantFilter
        The tenant domain or GUID to filter by (used as partition key)

    .PARAMETER Type
        Optional. The data type to filter by (e.g., Users, Groups, Devices)

    .EXAMPLE
        New-CIPPDbRequest -TenantFilter 'contoso.onmicrosoft.com'

    .EXAMPLE
        New-CIPPDbRequest -TenantFilter 'contoso.onmicrosoft.com' -Type 'Users'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$Type
    )

    try {
        # Enforce tenant lock when running inside custom script execution
        if ($script:CIPPLockedTenant) {
            $TenantFilter = $script:CIPPLockedTenant
        }

        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            throw 'TenantFilter is required.'
        }

        $Table = Get-CippTable -tablename 'CippReportingDB'

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -ExpandProperty defaultDomainName
        if (-not $Tenant) {
            if ($TenantFilter -eq $env:TenantID) {
                return $false
            }
            throw "Tenant '$TenantFilter' not found"
        }
        $SafeTenantFilter = ConvertTo-CIPPODataFilterValue -Value $Tenant -Type String
        $SafeTypeFilter = if ($Type) { ConvertTo-CIPPODataFilterValue -Value $Type -Type String } else { $null }

        if ($Type) {
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}.'" -f $SafeTenantFilter, $SafeTypeFilter
        } else {
            $Filter = "PartitionKey eq '{0}'" -f $SafeTenantFilter
        }

        $Results = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        return ($Results.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)
    } catch {
        Write-LogMessage -API 'CIPPDbRequest' -tenant $TenantFilter -message "Failed to query database: $($_.Exception.Message)" -sev Error
        throw
    }
}

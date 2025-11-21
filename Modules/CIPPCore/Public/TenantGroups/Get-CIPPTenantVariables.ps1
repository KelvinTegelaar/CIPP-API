function Get-CIPPTenantVariables {
    <#
    .SYNOPSIS
        Retrieves custom variables for a specific tenant
    .DESCRIPTION
        This function retrieves custom variables from the CippReplacemap table for a specific tenant,
        including both tenant-specific and global (AllTenants) variables. Tenant-specific variables
        take precedence over global variables.
    .PARAMETER TenantFilter
        The tenant filter (customerId or defaultDomainName)
    .PARAMETER IncludeGlobal
        Include global variables (AllTenants) in the results
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPTenantVariables -TenantFilter 'contoso.com'
    .EXAMPLE
        Get-CIPPTenantVariables -TenantFilter 'eda053f2-4add-41dc-9feb-78a5fc0934c9' -IncludeGlobal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [switch]$IncludeGlobal
    )

    try {
        $ReplaceTable = Get-CIPPTable -tablename 'CippReplacemap'
        $Variables = @{}

        # Get tenant information to resolve both customerId and defaultDomainName
        $Tenant = Get-Tenants -TenantFilter $TenantFilter
        if (!$Tenant) {
            Write-Warning "Tenant not found: $TenantFilter"
            return $Variables
        }

        # Load global variables first if requested (lower priority)
        if ($IncludeGlobal) {
            $GlobalMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq 'AllTenants'"
            if ($GlobalMap) {
                foreach ($Var in $GlobalMap) {
                    $Variables[$Var.RowKey] = @{
                        Value       = $Var.Value
                        Description = $Var.Description
                        Scope       = 'Global'
                    }
                }
            }
        }

        # Load tenant-specific variables (higher priority - will overwrite global)
        # Try by customerId first
        $TenantMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$($Tenant.customerId)'"

        # If no results found by customerId, try by defaultDomainName
        if (!$TenantMap) {
            $TenantMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$($Tenant.defaultDomainName)'"
        }

        if ($TenantMap) {
            foreach ($Var in $TenantMap) {
                $Variables[$Var.RowKey] = @{
                    Value       = $Var.Value
                    Description = $Var.Description
                    Scope       = 'Tenant'
                }
            }
        }

        return $Variables

    } catch {
        Write-LogMessage -API 'TenantGroups' -message "Failed to retrieve tenant variables for $TenantFilter : $($_.Exception.Message)" -sev Error
        return @{}
    }
}

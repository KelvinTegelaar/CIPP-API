function Set-CIPPDriftDeviation {
    <#
    .SYNOPSIS
        Sets the status of a drift deviation in the tenant drift table
    .DESCRIPTION
        This function stores drift deviation status changes in the tenantDrift table.
        It tracks when deviations are accepted, denied, or marked as customer specific.
    .PARAMETER TenantFilter
        The tenant filter (used as PartitionKey)
    .PARAMETER StandardName
        The standard name (used as RowKey, with '.' replaced by '_')
    .PARAMETER Status
        The status to set. Valid values: Accepted, New, Denied, CustomerSpecific
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Set-CIPPDriftDeviation -TenantFilter "contoso.onmicrosoft.com" -StandardName "IntuneTemplates.12345" -Status "Accepted"
    .EXAMPLE
        Set-CIPPDriftDeviation -TenantFilter "contoso.onmicrosoft.com" -StandardName "standards.passwordComplexity" -Status "CustomerSpecific"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$StandardName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Accepted', 'New', 'Denied', 'CustomerSpecific', 'DeniedRemediate', 'DeniedDelete')]
        [string]$Status
    )

    try {
        $Table = Get-CippTable -tablename 'tenantDrift'
        $RowKey = $StandardName -replace '\.', '_'
        $Entity = @{
            PartitionKey = $TenantFilter
            RowKey       = $RowKey
            StandardName = $StandardName
            Status       = $Status
            LastModified = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $Result = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

        Write-Verbose "Successfully set drift deviation status for $StandardName to $Status"
        return "Successfully set drift deviation status for $StandardName to $Status"

    } catch {
        Write-Error "Error setting drift deviation status: $($_.Exception.Message)"
        throw
    }
}

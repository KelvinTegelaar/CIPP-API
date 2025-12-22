function Add-CIPPDbItem {
    <#
    .SYNOPSIS
        Add items to the CIPP Reporting database

    .DESCRIPTION
        Adds items to the CippReportingDB table with support for bulk inserts and count mode

    .PARAMETER TenantFilter
        The tenant domain or GUID (used as partition key)

    .PARAMETER Type
        The type of data being stored (used in row key)

    .PARAMETER Data
        Array of items to add to the database

    .PARAMETER Count
        If specified, stores a single row with count of each object property as separate properties

    .EXAMPLE
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Groups' -Data $GroupsData

    .EXAMPLE
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Groups' -Data $GroupsData -Count
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Data,

        [Parameter(Mandatory = $false)]
        [switch]$Count
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'

        if ($Count) {
            $Entity = @{
                PartitionKey = $TenantFilter
                RowKey       = "$Type-Count"
                DataCount    = [int]$Data.Count
            }

            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

        } else {
            $Entities = foreach ($Item in $Data) {
                $ItemId = $Item.id
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = "$Type-$ItemId"
                    Data         = [string]($Item | ConvertTo-Json -Depth 10 -Compress)
                    Type         = $Type
                }
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entities -Force | Out-Null

        }

        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Added $($Data.Count) items of type $Type$(if ($Count) { ' (count mode)' })" -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to add items of type $Type : $($_.Exception.Message)" -sev Error
        throw
    }
}

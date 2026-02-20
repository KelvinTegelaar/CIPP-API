function Update-CIPPDbItem {
    <#
    .SYNOPSIS
        Update a single item in the CIPP Reporting database

    .DESCRIPTION
        Updates a single item in the CippReportingDB table by finding it by ItemId and updating its Data field.
        Supports full object replacement or partial property updates.

    .PARAMETER TenantFilter
        The tenant domain or GUID (used as partition key)

    .PARAMETER Type
        The type of data being stored (used in row key)

    .PARAMETER ItemId
        The unique identifier for the item to update

    .PARAMETER InputObject
        The updated object to store (will be converted to JSON). Used for full replacement.

    .PARAMETER PropertyUpdates
        Hashtable of property names and values to update in the existing cached object. More efficient than full replacement.

    .EXAMPLE
        Update-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'MailboxRules' -ItemId 'rule-guid' -InputObject $UpdatedRule

    .EXAMPLE
        Update-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'MailboxRules' -ItemId 'rule-guid' -PropertyUpdates @{Enabled = $true}
    #>
    [CmdletBinding(DefaultParameterSetName = 'FullObject')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$ItemId,

        [Parameter(Mandatory = $true, ParameterSetName = 'FullObject')]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'PartialUpdate')]
        [hashtable]$PropertyUpdates
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'

        # Format RowKey
        $RowKey = "$Type-$ItemId" -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', ''

        # Get existing entity
        $Filter = "PartitionKey eq '$TenantFilter' and RowKey eq '$RowKey'"
        $ExistingEntity = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $ExistingEntity) {
            Write-Information "[CIPPDbItem] Item not found for update: Tenant=$TenantFilter, Type=$Type, ItemId=$ItemId."
            return
        }

        # Determine the data to store
        if ($PSCmdlet.ParameterSetName -eq 'PartialUpdate') {
            # Parse existing data and update specific properties
            $ExistingData = $ExistingEntity.Data | ConvertFrom-Json
            foreach ($key in $PropertyUpdates.GetEnumerator()) {
                $ExistingData.($key.Name) = $key.Value
            }
            $DataToStore = $ExistingData
        } else {
            # Full object replacement
            $DataToStore = $InputObject
        }

        # Update entity
        $Entity = @{
            PartitionKey = $TenantFilter
            RowKey       = $RowKey
            Data         = [string]($DataToStore | ConvertTo-Json -Depth 10 -Compress)
            Type         = $Type
            ETag         = $ExistingEntity.ETag
        }

        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter `
            -message "Updated cached item: $Type - $ItemId" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter `
            -message "Failed to update item $Type - $ItemId : $($_.Exception.Message)" -sev Error `
            -LogData (Get-CippException -Exception $_)
        throw
    }
}

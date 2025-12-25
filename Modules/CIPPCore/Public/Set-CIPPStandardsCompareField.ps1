function Set-CIPPStandardsCompareField {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        $FieldName,
        $FieldValue,
        $TenantFilter,
        [Parameter()]
        [array]$BulkFields
    )
    $Table = Get-CippTable -tablename 'CippStandardsReports'
    $TenantName = Get-Tenants -TenantFilter $TenantFilter

    # Helper function to normalize field values
    function ConvertTo-NormalizedFieldValue {
        param($Value)
        if ($Value -is [System.Boolean]) {
            return [bool]$Value
        } elseif ($Value -is [string]) {
            return [string]$Value
        } else {
            $JsonValue = ConvertTo-Json -Compress -InputObject @($Value) -Depth 10 | Out-String
            return [string]$JsonValue
        }
    }

    # Handle bulk operations
    if ($BulkFields) {
        # Get all existing entities for this tenant in one query
        $ExistingEntities = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($TenantName.defaultDomainName)'"
        $ExistingHash = @{}
        foreach ($Entity in $ExistingEntities) {
            $ExistingHash[$Entity.RowKey] = $Entity
        }

        # Build array of entities to insert/update
        $EntitiesToProcess = [System.Collections.Generic.List[object]]::new()
        
        foreach ($Field in $BulkFields) {
            $NormalizedValue = ConvertTo-NormalizedFieldValue -Value $Field.FieldValue
            
            if ($ExistingHash.ContainsKey($Field.FieldName)) {
                $Entity = $ExistingHash[$Field.FieldName]
                $Entity.Value = $NormalizedValue
                $Entity | Add-Member -NotePropertyName TemplateId -NotePropertyValue ([string]$script:CippStandardInfoStorage.Value.StandardTemplateId) -Force
            } else {
                $Entity = [PSCustomObject]@{
                    PartitionKey = [string]$TenantName.defaultDomainName
                    RowKey       = [string]$Field.FieldName
                    Value        = $NormalizedValue
                    TemplateId   = [string]$script:CippStandardInfoStorage.Value.StandardTemplateId
                }
            }
            $EntitiesToProcess.Add($Entity)
        }

        if ($PSCmdlet.ShouldProcess('CIPP Standards Compare', "Set $($EntitiesToProcess.Count) fields for tenant '$($TenantName.defaultDomainName)'")) {
            try {
                # Single bulk insert/update operation
                Add-CIPPAzDataTableEntity @Table -Entity $EntitiesToProcess -Force
                Write-Information "Bulk added $($EntitiesToProcess.Count) fields to StandardCompare for $($TenantName.defaultDomainName)"
            } catch {
                Write-Warning "Failed to bulk add fields to StandardCompare for $($TenantName.defaultDomainName) - $($_.Exception.Message)"
            }
        }
    } else {
        # Original single field logic
        $NormalizedValue = ConvertTo-NormalizedFieldValue -Value $FieldValue
        $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($TenantName.defaultDomainName)' and RowKey eq '$($FieldName)'"

        if ($PSCmdlet.ShouldProcess('CIPP Standards Compare', "Set field '$FieldName' to '$NormalizedValue' for tenant '$($TenantName.defaultDomainName)'")) {
            try {
                if ($Existing) {
                    $Existing.Value = $NormalizedValue
                    $Existing | Add-Member -NotePropertyName TemplateId -NotePropertyValue ([string]$script:CippStandardInfoStorage.Value.StandardTemplateId) -Force
                    Add-CIPPAzDataTableEntity @Table -Entity $Existing -Force
                } else {
                    $Result = [PSCustomObject]@{
                        PartitionKey = [string]$TenantName.defaultDomainName
                        RowKey       = [string]$FieldName
                        Value        = $NormalizedValue
                        TemplateId   = [string]$script:CippStandardInfoStorage.Value.StandardTemplateId
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $Result -Force
                }
                Write-Information "Adding $FieldName to StandardCompare for $($TenantName.defaultDomainName). content is $NormalizedValue"
            } catch {
                Write-Warning "Failed to add $FieldName to StandardCompare for $($TenantName.defaultDomainName). content is $NormalizedValue - $($_.Exception.Message)"
            }
        }
    }
}

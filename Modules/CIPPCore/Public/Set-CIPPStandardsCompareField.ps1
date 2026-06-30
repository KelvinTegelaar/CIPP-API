function Set-CIPPStandardsCompareField {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        $FieldName,
        $FieldValue, #FieldValue is here for backward compatibility.
        $CurrentValue, #The latest actual value in raw json
        $ExpectedValue, #The expected value - e.g. the settings object from our standard
        $TenantFilter,
        [Parameter()]
        [bool]$LicenseAvailable = $true,
        [Parameter()]
        [array]$BulkFields
    )
    $Table = Get-CippTable -tablename 'CippStandardsReports'
    $TenantName = Get-Tenants -TenantFilter $TenantFilter

    # Helper function to normalize field values. This can go in a couple of releases tbh.
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
    function ConvertTo-NormalizedJson {
        param([string]$JsonString)

        if ([string]::IsNullOrEmpty($JsonString)) {
            return $JsonString
        }
        #Replace quoted numbers with unquoted numbers for consistent comparison
        $JsonString = $JsonString -replace ':"(\d+)"([,}])', ':$1$2'
        return $JsonString
    }

        function ConvertTo-SortedObject {
        param($Value)

        if ($null -eq $Value) { return $null }

        if ($Value -is [string] -or $Value -is [bool] -or $Value -is [System.ValueType]) {
            return $Value
        }

        if ($Value -is [System.Collections.IDictionary]) {
            $Sorted = [ordered]@{}
            foreach ($Key in ($Value.Keys | Sort-Object)) {
                $Sorted[$Key] = ConvertTo-SortedObject -Value $Value[$Key]
            }
            return $Sorted
        }

        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $Sorted = [ordered]@{}
            foreach ($Name in ($Value.PSObject.Properties.Name | Sort-Object)) {
                $Sorted[$Name] = ConvertTo-SortedObject -Value $Value.$Name
            }
            return $Sorted
        }

        if ($Value -is [System.Collections.IEnumerable]) {
            $Carriers = foreach ($Item in $Value) {
                $SortedItem = ConvertTo-SortedObject -Value $Item
                [PSCustomObject]@{
                    SortKey = [string](ConvertTo-Json -InputObject $SortedItem -Depth 10 -Compress)
                    Item    = $SortedItem
                }
            }
            $Result = [System.Collections.Generic.List[object]]::new()
            foreach ($Carrier in @($Carriers | Sort-Object -Property SortKey)) {
                $Result.Add($Carrier.Item)
            }
            return , $Result.ToArray()
        }

        return $Value
    }

    function ConvertTo-CanonicalJsonString {
        param($Value)

        if ($null -eq $Value) { return $Value }

        $ToSort = $Value
        if ($Value -is [string]) {
            try {
                $ToSort = ConvertFrom-Json -InputObject $Value -ErrorAction Stop
            } catch {
                return $Value
            }
        }

        $Json = [string](ConvertTo-Json -InputObject (ConvertTo-SortedObject -Value $ToSort) -Depth 10 -Compress)
        return ConvertTo-NormalizedJson -JsonString $Json
    }

    if ($CurrentValue) {
        $CurrentValue = ConvertTo-CanonicalJsonString -Value $CurrentValue
    }
    if ($ExpectedValue) {
        $ExpectedValue = ConvertTo-CanonicalJsonString -Value $ExpectedValue
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
                $Entity | Add-Member -NotePropertyName LicenseAvailable -NotePropertyValue ([bool]$Field.LicenseAvailable) -Force
                $Entity | Add-Member -NotePropertyName CurrentValue -NotePropertyValue ([string]$Field.CurrentValue) -Force
                $Entity | Add-Member -NotePropertyName ExpectedValue -NotePropertyValue ([string]$Field.ExpectedValue) -Force
            } else {
                $Entity = [PSCustomObject]@{
                    PartitionKey     = [string]$TenantName.defaultDomainName
                    RowKey           = [string]$Field.FieldName
                    Value            = $NormalizedValue
                    TemplateId       = [string]$script:CippStandardInfoStorage.Value.StandardTemplateId
                    LicenseAvailable = [bool]$Field.LicenseAvailable
                    CurrentValue     = [string]$Field.CurrentValue
                    ExpectedValue    = [string]$Field.ExpectedValue
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
                    $Existing | Add-Member -NotePropertyName LicenseAvailable -NotePropertyValue ([bool]$LicenseAvailable) -Force
                    $Existing | Add-Member -NotePropertyName CurrentValue -NotePropertyValue ([string]$CurrentValue) -Force
                    $Existing | Add-Member -NotePropertyName ExpectedValue -NotePropertyValue ([string]$ExpectedValue) -Force
                    Add-CIPPAzDataTableEntity @Table -Entity $Existing -Force
                } else {
                    $Result = [PSCustomObject]@{
                        PartitionKey     = [string]$TenantName.defaultDomainName
                        RowKey           = [string]$FieldName
                        Value            = $NormalizedValue
                        TemplateId       = [string]$script:CippStandardInfoStorage.Value.StandardTemplateId
                        LicenseAvailable = [bool]$LicenseAvailable
                        CurrentValue     = [string]$CurrentValue
                        ExpectedValue    = [string]$ExpectedValue
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

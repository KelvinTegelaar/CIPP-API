function Add-CIPPAzDataTableEntity {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'OperationType')]
    param(
        $Context,
        $Entity,
        [switch]$CreateTableIfNotExists,

        [Parameter(ParameterSetName = 'Force')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'OperationType')]
        [ValidateSet('Add', 'UpsertMerge', 'UpsertReplace')]
        [string]$OperationType = 'Add'
    )

    # Validate input parameters
    if ($null -eq $Context) {
        throw 'Context parameter cannot be null'
    }

    if ($null -eq $Entity) {
        Write-Warning 'Entity parameter is null - nothing to process'
        return
    }

    $Parameters = @{
        Context                = $Context
        CreateTableIfNotExists = $CreateTableIfNotExists
    }
    if ($PSCmdlet.ParameterSetName -eq 'Force') {
        $Parameters.Force = $Force
    } else {
        $Parameters.OperationType = $OperationType
    }

    $MaxRowSize = 500000 - 100
    $MaxSize = 30kb

    foreach ($SingleEnt in @($Entity)) {
        try {
            # Skip null entities
            if ($null -eq $SingleEnt) {
                Write-Warning 'Skipping null entity'
                continue
            }

            if ($null -eq $SingleEnt.PartitionKey -or $null -eq $SingleEnt.RowKey) {
                throw 'PartitionKey or RowKey is null'
            }

            # Ensure entity is not empty
            if ($SingleEnt -is [hashtable] -and $SingleEnt.Count -eq 0) {
                Write-Warning 'Skipping empty hashtable entity'
                continue
            } elseif ($SingleEnt -is [PSCustomObject] -and ($SingleEnt.PSObject.Properties | Measure-Object).Count -eq 0) {
                Write-Warning 'Skipping empty PSCustomObject entity'
                continue
            }

            # Additional validation for AzBobbyTables compatibility
            try {
                # Ensure all property values are not null for string properties
                if ($SingleEnt -is [hashtable]) {
                    foreach ($key in @($SingleEnt.Keys)) {
                        if ($null -eq $SingleEnt[$key]) {
                            $SingleEnt.Remove($key)
                        }
                    }
                } elseif ($SingleEnt -is [PSCustomObject]) {
                    $propsToRemove = [system.Collections.Generic.List[string]]::new()
                    foreach ($prop in $SingleEnt.PSObject.Properties) {
                        if ($null -eq $prop.Value) {
                            $propsToRemove.Add($prop.Name)
                        }
                    }
                    foreach ($propName in $propsToRemove) {
                        $SingleEnt.PSObject.Properties.Remove($propName)
                    }
                }
            } catch {
                Write-Warning "Error during entity validation: $($_.Exception.Message)"
            }

            Add-AzDataTableEntity @Parameters -Entity $SingleEnt -ErrorAction Stop

        } catch [System.Exception] {
            if ($_.Exception.ErrorCode -in @('PropertyValueTooLarge', 'EntityTooLarge', 'RequestBodyTooLarge')) {
                try {
                    Write-Information 'Entity is too large. Splitting entity into multiple parts.'

                    $largePropertyNames = [System.Collections.Generic.List[string]]::new()
                    $entitySize = 0

                    if ($SingleEnt -is [System.Management.Automation.PSCustomObject]) {
                        $SingleEnt = $SingleEnt | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -AsHashtable
                    }

                    foreach ($key in $SingleEnt.Keys) {
                        $propertySize = [System.Text.Encoding]::UTF8.GetByteCount($SingleEnt[$key].ToString())
                        $entitySize += $propertySize
                        if ($propertySize -gt $MaxSize) {
                            $largePropertyNames.Add($key)
                        }
                    }

                    if (($largePropertyNames | Measure-Object).Count -gt 0) {
                        $splitInfoList = [System.Collections.Generic.List[object]]::new()
                        foreach ($largePropertyName in $largePropertyNames) {
                            $dataString = $SingleEnt[$largePropertyName]
                            $splitCount = [math]::Ceiling($dataString.Length / $MaxSize)
                            $splitData = [System.Collections.Generic.List[object]]::new()
                            for ($i = 0; $i -lt $splitCount; $i++) {
                                $start = $i * $MaxSize
                                $splitData.Add($dataString.Substring($start, [Math]::Min($MaxSize, $dataString.Length - $start))) > $null
                            }
                            $splitDataCount = $splitData.Count
                            $splitPropertyNames = [System.Collections.Generic.List[object]]::new()
                            for ($i = 0; $i -lt $splitDataCount; $i++) {
                                $splitPropertyNames.Add("${largePropertyName}_Part$i")
                            }

                            $splitInfo = @{
                                OriginalHeader = $largePropertyName
                                SplitHeaders   = $splitPropertyNames
                            }
                            $splitInfoList.Add($splitInfo)
                            $SingleEnt.Remove($largePropertyName)

                            for ($i = 0; $i -lt $splitDataCount; $i++) {
                                $SingleEnt[$splitPropertyNames[$i]] = $splitData[$i]
                            }
                        }
                        $SingleEnt['SplitOverProps'] = ($splitInfoList | ConvertTo-Json -Compress).ToString()
                    }

                    $entitySize = [System.Text.Encoding]::UTF8.GetByteCount($($SingleEnt | ConvertTo-Json -Compress))
                    if ($entitySize -gt $MaxRowSize) {
                        $rows = [System.Collections.Generic.List[object]]::new()
                        $originalPartitionKey = $SingleEnt.PartitionKey
                        $originalRowKey = $SingleEnt.RowKey
                        $entityIndex = 0

                        while ($entitySize -gt $MaxRowSize) {
                            Write-Information "Entity size is $entitySize. Splitting entity into multiple parts."
                            $newEntity = @{}
                            $newEntity['PartitionKey'] = $originalPartitionKey
                            $newEntity['RowKey'] = if ($entityIndex -eq 0) { $originalRowKey } else { "$($originalRowKey)-part$entityIndex" }
                            $newEntity['OriginalEntityId'] = $originalRowKey
                            $newEntity['PartIndex'] = $entityIndex
                            $entityIndex++

                            $propertiesToRemove = [System.Collections.Generic.List[object]]::new()
                            foreach ($key in $SingleEnt.Keys) {
                                if ($key -in @('RowKey', 'PartitionKey')) { continue }
                                $newEntitySize = [System.Text.Encoding]::UTF8.GetByteCount($($newEntity | ConvertTo-Json -Compress))
                                if ($newEntitySize -lt $MaxRowSize) {
                                    $propertySize = [System.Text.Encoding]::UTF8.GetByteCount($SingleEnt[$key].ToString())
                                    if ($propertySize -gt $MaxRowSize) {
                                        $dataString = $SingleEnt[$key]
                                        $splitCount = [math]::Ceiling($dataString.Length / $MaxSize)
                                        $splitData = [System.Collections.Generic.List[object]]::new()
                                        for ($i = 0; $i -lt $splitCount; $i++) {
                                            $start = $i * $MaxSize
                                            $splitData.Add($dataString.Substring($start, [Math]::Min($MaxSize, $dataString.Length - $start))) > $null
                                        }

                                        $splitPropertyNames = [System.Collections.Generic.List[object]]::new()
                                        for ($i = 0; $i -lt $splitData.Count; $i++) {
                                            $splitPropertyNames.Add("${key}_Part$i")
                                        }

                                        for ($i = 0; $i -lt $splitData.Count; $i++) {
                                            $newEntity[$splitPropertyNames[$i]] = $splitData[$i]
                                        }
                                    } else {
                                        $newEntity[$key] = $SingleEnt[$key]
                                    }
                                    $propertiesToRemove.Add($key)
                                }
                            }

                            foreach ($prop in $propertiesToRemove) {
                                $SingleEnt.Remove($prop)
                            }

                            $rows.Add($newEntity)
                            $entitySize = [System.Text.Encoding]::UTF8.GetByteCount($($SingleEnt | ConvertTo-Json -Compress))
                        }

                        if ($SingleEnt.Count -gt 0) {
                            $SingleEnt['RowKey'] = "$($originalRowKey)-part$entityIndex"
                            $SingleEnt['OriginalEntityId'] = $originalRowKey
                            $SingleEnt['PartIndex'] = $entityIndex
                            $SingleEnt['PartitionKey'] = $originalPartitionKey
                            $rows.Add($SingleEnt)
                        }

                        foreach ($row in $rows) {
                            Write-Information "current entity is $($row.RowKey) with $($row.PartitionKey). Our size is $([System.Text.Encoding]::UTF8.GetByteCount($($row | ConvertTo-Json -Compress)))"
                            $NewRow = ([PSCustomObject]$row) | Select-Object * -ExcludeProperty Timestamp
                            Add-AzDataTableEntity @Parameters -Entity $NewRow
                        }

                    } else {
                        $NewEnt = ([PSCustomObject]$SingleEnt) | Select-Object * -ExcludeProperty Timestamp
                        Add-AzDataTableEntity @Parameters -Entity $NewEnt
                        if ($NewEnt.PSObject.Properties['OriginalEntityId'] -eq $null -and $NewEnt.PSObject.Properties['PartIndex'] -eq $null) {
                            $partIndex = 1
                            while ($true) {
                                $partRowKey = "$($NewEnt.RowKey)-part$partIndex"
                                try {
                                    Remove-AzDataTableEntity -Context $Context -PartitionKey $NewEnt.PartitionKey -RowKey $partRowKey -ErrorAction Stop
                                    Write-Information "Deleted obsolete part: $partRowKey"
                                    $partIndex++
                                } catch {
                                    break
                                }
                            }
                        }
                    }

                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-Warning 'AzBobbyTables Error'
                    throw "Error processing entity: $ErrorMessage Linenumber: $($_.InvocationInfo.ScriptLineNumber)"
                }
            } else {
                try { Write-Information ($_.Exception | ConvertTo-Json) } catch { Write-Information $_.Exception }
                Write-Information "THE ERROR IS $($_.Exception.message). The size of the entity is $entitySize."
                Write-Information "Parameters are: $($Parameters | ConvertTo-Json -Compress)"
                Write-Information $_.InvocationInfo.PositionMessage
                throw $_
            }
        }
    }
}

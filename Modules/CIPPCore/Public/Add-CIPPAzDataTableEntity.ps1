function Add-CIPPAzDataTableEntity {
    [CmdletBinding()]
    param(
        $Context,
        $Entity,
        [switch]$Force,
        [switch]$CreateTableIfNotExists
    )

    $MaxRowSize = 500000 - 100 # Maximum size of an entity
    $MaxSize = 30kb # Maximum size of a property value

    foreach ($SingleEnt in @($Entity)) {
        try {
            if ($null -eq $SingleEnt.PartitionKey -or $null -eq $SingleEnt.RowKey) {
                throw 'PartitionKey or RowKey is null'
            }
            Add-AzDataTableEntity -Context $Context -Force:$Force -CreateTableIfNotExists:$CreateTableIfNotExists -Entity $SingleEnt -ErrorAction Stop
        } catch [System.Exception] {
            if ($_.Exception.ErrorCode -eq 'PropertyValueTooLarge' -or $_.Exception.ErrorCode -eq 'EntityTooLarge' -or $_.Exception.ErrorCode -eq 'RequestBodyTooLarge') {
                try {
                    $largePropertyNames = [System.Collections.Generic.List[string]]::new()
                    $entitySize = 0

                    # Convert $SingleEnt to hashtable if it is a PSObject
                    if ($SingleEnt -is [System.Management.Automation.PSCustomObject]) {
                        $SingleEnt = $SingleEnt | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
                    }

                    foreach ($key in $SingleEnt.Keys) {
                        $propertySize = [System.Text.Encoding]::UTF8.GetByteCount($SingleEnt[$key].ToString())
                        $entitySize = $entitySize + $propertySize
                        if ($propertySize -gt $MaxSize) {
                            $largePropertyNames.Add($key)
                        }
                    }

                    if ($largePropertyNames.Count -gt 0) {
                        $splitInfoList = [System.Collections.Generic.List[object]]::new()
                        foreach ($largePropertyName in $largePropertyNames) {
                            $dataString = $SingleEnt[$largePropertyName]
                            $splitCount = [math]::Ceiling($dataString.Length / $MaxSize)
                            $splitData = [System.Collections.Generic.List[object]]::new()
                            for ($i = 0; $i -lt $splitCount; $i++) {
                                $start = $i * $MaxSize
                                $splitData.Add($dataString.Substring($start, [Math]::Min($MaxSize, $dataString.Length - $start))) > $null
                            }

                            $splitPropertyNames = [System.Collections.Generic.List[object]]::new()
                            for ($i = 0; $i -lt $splitData.Count; $i++) {
                                $splitPropertyNames.Add("${largePropertyName}_Part$i") > $null
                            }

                            $splitInfo = @{
                                OriginalHeader = $largePropertyName
                                SplitHeaders   = $splitPropertyNames
                            }
                            $splitInfoList.Add($splitInfo) > $null
                            $SingleEnt.Remove($largePropertyName)

                            for ($i = 0; $i -lt $splitData.Count; $i++) {
                                $SingleEnt[$splitPropertyNames[$i]] = $splitData[$i]
                            }
                        }

                        $SingleEnt['SplitOverProps'] = ($splitInfoList | ConvertTo-Json -Compress).ToString()
                    }

                    # Check if the entity is still too large
                    $entitySize = [System.Text.Encoding]::UTF8.GetByteCount($($SingleEnt | ConvertTo-Json))
                    if ($entitySize -gt $MaxRowSize) {
                        $rows = [System.Collections.Generic.List[object]]::new()
                        $originalPartitionKey = $SingleEnt.PartitionKey
                        $originalRowKey = $SingleEnt.RowKey
                        $entityIndex = 0

                        while ($entitySize -gt $MaxRowSize) {
                            Write-Information "Entity size is $entitySize. Splitting entity into multiple parts."
                            $newEntity = @{}
                            $newEntity['PartitionKey'] = $originalPartitionKey
                            if ($entityIndex -eq 0) {
                                $newEntity['RowKey'] = $originalRowKey
                            } else {
                                $newEntity['RowKey'] = "$($originalRowKey)-part$entityIndex"
                            }
                            $newEntity['OriginalEntityId'] = $originalRowKey
                            $newEntity['PartIndex'] = $entityIndex
                            $entityIndex++

                            $propertiesToRemove = [System.Collections.Generic.List[object]]::new()
                            foreach ($key in $SingleEnt.Keys) {
                                $newEntitySize = [System.Text.Encoding]::UTF8.GetByteCount($($newEntity | ConvertTo-Json))
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
                                            $splitPropertyNames.Add("${key}_Part$i") > $null
                                        }

                                        for ($i = 0; $i -lt $splitData.Count; $i++) {
                                            $newEntity[$splitPropertyNames[$i]] = $splitData[$i]
                                        }
                                    } else {
                                        $newEntity[$key] = $SingleEnt[$key]
                                    }
                                    $propertiesToRemove.Add($key) > $null
                                }
                            }

                            foreach ($prop in $propertiesToRemove) {
                                $SingleEnt.Remove($prop)
                            }

                            $rows.Add($newEntity) > $null
                            $entitySize = [System.Text.Encoding]::UTF8.GetByteCount($($SingleEnt | ConvertTo-Json))
                        }

                        if ($SingleEnt.Count -gt 0) {
                            $SingleEnt['RowKey'] = "$($originalRowKey)-part$entityIndex"
                            $SingleEnt['OriginalEntityId'] = $originalRowKey
                            $SingleEnt['PartIndex'] = $entityIndex
                            $SingleEnt['PartitionKey'] = $originalPartitionKey

                            $rows.Add($SingleEnt) > $null
                        }

                        foreach ($row in $rows) {
                            Write-Information "current entity is $($row.RowKey) with $($row.PartitionKey). Our size is $([System.Text.Encoding]::UTF8.GetByteCount($($row | ConvertTo-Json)))"
                            Add-AzDataTableEntity -Context $Context -Force:$Force -CreateTableIfNotExists:$CreateTableIfNotExists -Entity $row
                        }
                    } else {
                        Add-AzDataTableEntity -Context $Context -Force:$Force -CreateTableIfNotExists:$CreateTableIfNotExists -Entity $SingleEnt
                    }

                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    throw "Error processing entity: $ErrorMessage Linenumber: $($_.InvocationInfo.ScriptLineNumber)"
                }
            } else {
                Write-Information "THE ERROR IS $($_.Exception.message). The size of the entity is $entitySize."
                throw $_
            }
        }
    }
}

function Get-CIPPAzDataTableEntity {
    [CmdletBinding()]
    param(
        $Context,
        $Filter,
        $Property,
        $First,
        $Skip,
        $Sort,
        $Count
    )

    $Results = Get-AzDataTableEntity @PSBoundParameters
    $mergedResults = @{}

    # First pass: Collect all parts and complete entities
    foreach ($entity in $Results) {
        if ($entity.OriginalEntityId) {
            $entityId = $entity.OriginalEntityId
            $partitionKey = $entity.PartitionKey
            if (-not $mergedResults.ContainsKey($partitionKey)) {
                $mergedResults[$partitionKey] = @{}
            }
            if (-not $mergedResults[$partitionKey].ContainsKey($entityId)) {
                $mergedResults[$partitionKey][$entityId] = @{
                    Parts = [System.Collections.Generic.List[object]]::new()
                }
            }
            $mergedResults[$partitionKey][$entityId]['Parts'].Add($entity)
        } else {
            $partitionKey = $entity.PartitionKey
            if (-not $mergedResults.ContainsKey($partitionKey)) {
                $mergedResults[$partitionKey] = @{}
            }
            $mergedResults[$partitionKey][$entity.RowKey] = @{
                Entity = $entity
                Parts  = [System.Collections.Generic.List[object]]::new()
            }
        }
    }

    $finalResults = [System.Collections.Generic.List[object]]::new()
    foreach ($partitionKey in $mergedResults.Keys) {
        foreach ($entityId in $mergedResults[$partitionKey].Keys) {
            $entityData = $mergedResults[$partitionKey][$entityId]
            if (($entityData.Parts | Measure-Object).Count -gt 0) {
                $fullEntity = [PSCustomObject]@{}
                $parts = $entityData.Parts | Sort-Object PartIndex
                foreach ($part in $parts) {
                    foreach ($key in $part.PSObject.Properties.Name) {
                        if ($key -notin @('OriginalEntityId', 'PartIndex', 'PartitionKey', 'RowKey', 'Timestamp')) {
                            if ($fullEntity.PSObject.Properties[$key]) {
                                $fullEntity | Add-Member -MemberType NoteProperty -Name $key -Value ($fullEntity.$key + $part.$key) -Force
                            } else {
                                $fullEntity | Add-Member -MemberType NoteProperty -Name $key -Value $part.$key
                            }
                        }
                    }
                }
                $fullEntity | Add-Member -MemberType NoteProperty -Name 'PartitionKey' -Value $parts[0].PartitionKey -Force
                $fullEntity | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value $entityId -Force
                $fullEntity | Add-Member -MemberType NoteProperty -Name 'Timestamp' -Value $parts[0].Timestamp -Force
                $finalResults.Add($fullEntity)
            } else {
                $FinalResults.Add($entityData.Entity)
            }
        }
    }

    foreach ($entity in $finalResults) {
        if ($entity.SplitOverProps) {
            $splitInfoList = $entity.SplitOverProps | ConvertFrom-Json
            foreach ($splitInfo in $splitInfoList) {
                $mergedData = [string]::Join('', ($splitInfo.SplitHeaders | ForEach-Object { $entity.$_ }))
                $entity | Add-Member -NotePropertyName $splitInfo.OriginalHeader -NotePropertyValue $mergedData -Force
                $propsToRemove = $splitInfo.SplitHeaders
                foreach ($prop in $propsToRemove) {
                    $entity.PSObject.Properties.Remove($prop)
                }
            }
            $entity.PSObject.Properties.Remove('SplitOverProps')
        }
    }

    return $finalResults
}

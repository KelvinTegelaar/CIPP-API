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

    foreach ($entity in $Results) {
        if ($entity.OriginalEntityId) {
            $entityId = $entity.OriginalEntityId
            if (-not $mergedResults.ContainsKey($entityId)) {
                $mergedResults[$entityId] = @{
                    Parts = @()
                }
            }
            $mergedResults[$entityId]['Parts'] = $mergedResults[$entityId]['Parts'] + @($entity)
        } else {
            $mergedResults[$entity.RowKey] = @{
                Entity = $entity
                Parts  = @()
            }
        }
    }

    $finalResults = @()
    foreach ($entityId in $mergedResults.Keys) {
        $entityData = $mergedResults[$entityId]
        if ($entityData.Parts.Count -gt 0) {
            $fullEntity = [PSCustomObject]@{}
            $parts = $entityData.Parts | Sort-Object PartIndex
            foreach ($part in $parts) {
                foreach ($key in $part.PSObject.Properties.Name) {
                    if ($key -notin @('OriginalEntityId', 'PartIndex', 'PartitionKey', 'RowKey', 'ETag', 'Timestamp')) {
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
            $finalResults = $finalResults + @($fullEntity)
        } else {
            $finalResults = $finalResults + @($entityData.Entity)
        }
    }

    foreach ($entity in $finalResults) {
        if ($entity.SplitOverProps) {
            $splitInfo = $entity.SplitOverProps | ConvertFrom-Json
            $mergedData = [string]::Join('', ($splitInfo.SplitHeaders | ForEach-Object { $entity.$_ }))
            $entity | Add-Member -NotePropertyName $splitInfo.OriginalHeader -NotePropertyValue $mergedData -Force
            $propsToRemove = $splitInfo.SplitHeaders + 'SplitOverProps'
            foreach ($prop in $propsToRemove) {
                $entity.PSObject.Properties.Remove($prop)
            }
        }
    }

    return $finalResults
}

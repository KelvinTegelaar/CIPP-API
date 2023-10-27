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
    $Results = $Results | ForEach-Object {
        $entity = $_
        if ($entity.SplitOverProps) {
            $splitInfo = $entity.SplitOverProps | ConvertFrom-Json
            $mergedData = -join ($splitInfo.SplitHeaders | ForEach-Object { $entity.$_ })
            $entity | Add-Member -NotePropertyName $splitInfo.OriginalHeader -NotePropertyValue $mergedData -Force
            $propsToRemove = $splitInfo.SplitHeaders + "SplitOverProps"
            $entity = $entity | Select-Object * -ExcludeProperty $propsToRemove
            $entity 
        }
        else {
            $entity  
        }
    }
    
    return $Results
}

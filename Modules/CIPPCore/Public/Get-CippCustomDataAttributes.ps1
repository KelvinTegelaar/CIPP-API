function Get-CippCustomDataAttributes {
    <#
    .SYNOPSIS
        Get the custom data attributes for CIPP
    .DESCRIPTION
        This function is used to get the custom data attributes for CIPP
    #>
    [CmdletBinding()]
    param(
        $TargetObject = 'All'
    )
    $CustomDataTable = Get-CippTable -tablename 'CustomData'
    $CustomDataEntities = Get-CIPPAzDataTableEntity @CustomDataTable
    $AvailableAttributes = foreach ($CustomDataEntity in $CustomDataEntities) {
        $Type = $CustomDataEntity.PartitionKey
        $CustomData = $CustomDataEntity.JSON | ConvertFrom-Json
        if ($CustomData) {
            if ($Type -eq 'SchemaExtension') {
                $Name = $CustomData.id
                foreach ($TargetObject in $CustomData.targetTypes) {
                    [PSCustomObject]@{
                        name         = $Name
                        type         = $Type
                        targetObject = $TargetObject.ToLower()
                        properties   = $CustomData.properties
                    }
                }
            } elseif ($Type -eq 'DirectoryExtension') {
                $Name = $CustomData.RowKey
                foreach ($TargetObject in $CustomData.targetObjects) {
                    [PSCustomObject]@{
                        name          = $Name
                        type          = $Type
                        targetObject  = $TargetObject
                        dataType      = $CustomData.dataType
                        isMultiValued = $CustomData.isMultiValued
                    }
                }
            }
        }
    }

    if ($TargetObject -eq 'All') {
        return $AvailableAttributes
    } else {
        return $AvailableAttributes | Where-Object { $_.targetObject -eq $TargetObject }
    }
}

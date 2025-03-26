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
                    foreach ($Property in $CustomData.properties) {
                        [PSCustomObject]@{
                            name          = '{0}.{1}' -f $Name, $Property.name
                            type          = $Type
                            targetObject  = $TargetObject
                            dataType      = $Property.type
                            isMultiValued = $false
                        }
                    }
                }
            } elseif ($Type -eq 'DirectoryExtension') {
                $Name = $CustomDataEntity.RowKey
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

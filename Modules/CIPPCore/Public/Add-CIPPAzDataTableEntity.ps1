function Add-CIPPAzDataTableEntity {
    [CmdletBinding()]
    param(
        $Context,
        $Entity,
        $Force,
        $CreateTableIfNotExists
    )
    
    $Context = New-AzStorageContext -ConnectionString $ENV:AzureWebJobsStorage

    foreach ($SingleEnt in $Entity) {
        try {
            # Attempt to add the entity to the data table
            Add-AzDataTableEntity @PSBoundParameters -Entity $SingleEnt
        }
        catch [System.Exception] {
            if ($_.Exception.ErrorCode -eq "PropertyValueTooLarge" -or $_.Exception.ErrorCode -eq "EntityTooLarge") {
                try {
                    $DestinationFile = "$($SingleEnt.RowKey)-$($SingleEnt.PartitionKey).json"
                    $blob = Set-AzStorageBlobContent -File "blank.json" -Container "tableblobs" -Context $Context -Blob $DestinationFile -Force
                    $blob.ICloudBlob.uploadText(($SingleEnt | ConvertTo-Json -Compress -Depth 50))
                    Add-AzDataTableEntity @PSBoundParameters -Entity @{ RowKey = $SingleEnt.RowKey; PartitionKey = $SingleEnt.PartitionKey; BlobStorageContent = $true }
                }
                catch {
                    throw "Could not write to Blob Storage: $($_.Exception.Message)."
                }
            }
            else {
                throw $_
            }
        }
    }
}

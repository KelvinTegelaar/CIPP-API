function Get-CIPPAzDatatableEntity {
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
    $Context = New-AzStorageContext -ConnectionString $ENV:AzureWebJobsStorage

    $Results = $Results | ForEach-Object {
        if ($_.BlobStorageContent) {
            (Get-AzStorageBlobContent -Container 'tableblobs' -Blob "$($_.RowKey)-$($_.PartitionKey).json" -Context $Context -Force).ICloudBlob.DownloadText() | ConvertFrom-Json
        }
        else {
            $_
        }
    }
    
    return $Results
}

function Get-CIPPImageNameMap {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        The names given to the gallery images of one kind, as a hashtable of image id -> name.
    .DESCRIPTION
        A name lives on a small row of its own (PartitionKey imageMeta, RowKey the image id) rather
        than on the image row: an image payload is split across several entities, and renaming it
        must not mean rewriting them. Images that were never named are simply absent from the map.
    .PARAMETER PartitionKey
        The image kind the names belong to (logo, brandingCover).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PartitionKey
    )

    $Map = @{}
    try {
        $Table = Get-CIPPTable -TableName 'Images'
        $Rows = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'imageMeta' and kind eq '$($PartitionKey.Replace("'", "''"))'"
        foreach ($Row in @($Rows)) {
            if ($Row.RowKey -and -not [string]::IsNullOrWhiteSpace([string]$Row.name)) { $Map[[string]$Row.RowKey] = [string]$Row.name }
        }
    } catch {
        Write-Warning "Failed to read image names for '$PartitionKey': $($_.Exception.Message)"
    }
    return $Map
}

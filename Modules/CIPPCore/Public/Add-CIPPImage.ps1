function Add-CIPPImage {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Stores an image in the Images table and returns its id.
    .PARAMETER PartitionKey
        Image kind / purpose (e.g. logo, brandingCover).
    .PARAMETER Data
        Image as a data URL (data:image/...;base64,...). Max 2MB decoded.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PartitionKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Data
    )

    if ($Data -notmatch '^data:image\/([^;]+);base64,') {
        throw 'Invalid image format. Expected a data URL image (data:image/...;base64,...).'
    }

    $ContentType = "image/$($Matches[1])"
    $Base64Data = $Data -replace '^data:image\/[^;]+;base64,', ''
    try {
        $ImageBytes = [Convert]::FromBase64String($Base64Data)
    } catch {
        throw "Invalid base64 image data: $($_.Exception.Message)"
    }

    if ($ImageBytes.Length -gt 2097152) {
        throw 'Image size must be less than 2MB.'
    }

    $Id = [guid]::NewGuid().ToString()
    $Table = Get-CIPPTable -TableName 'Images'
    $Entity = @{
        PartitionKey = $PartitionKey
        RowKey       = $Id
        data         = $Data
        contentType  = $ContentType
        created      = (Get-Date).ToUniversalTime().ToString('o')
    }

    Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

    return @{
        id           = $Id
        partitionKey = $PartitionKey
        contentType  = $ContentType
    }
}

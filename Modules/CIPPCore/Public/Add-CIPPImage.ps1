function Add-CIPPImage {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Stores an image in the Images table and returns its id.
    .PARAMETER PartitionKey
        Image kind / purpose (e.g. logo, brandingCover).
    .PARAMETER Data
        Image as a data URL (data:image/...;base64,...). Max 5MB decoded.

        The ceiling is a payload-size choice, not a storage limit: Add-CIPPAzDataTableEntity splits
        oversized entities across properties and `{RowKey}-partN` rows, so the table service is not
        what constrains this. What does is that branding images are returned inline as data URLs in
        ListUserSettings on every page load, and base64 adds about a third to whatever is stored.
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

    $MaxImageBytes = 5242880
    if ($ImageBytes.Length -gt $MaxImageBytes) {
        throw 'Image size must be less than 5MB.'
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

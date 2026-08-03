function Remove-CIPPImage {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Removes one or more images from the Images table.
    .PARAMETER PartitionKey
        Image kind / purpose (e.g. logo, brandingCover). Required.
    .PARAMETER Id
        One or more image RowKey GUIDs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PartitionKey,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Id
    )

    $Ids = @($Id | Where-Object { $_ -and "$_".Trim() -ne '' } | ForEach-Object { "$_".Trim() } | Select-Object -Unique)
    if ($Ids.Count -eq 0) {
        return
    }

    $Table = Get-CIPPTable -TableName 'Images'
    foreach ($ImageId in $Ids) {
        $Entity = @{
            PartitionKey = $PartitionKey
            RowKey       = $ImageId
        }
        try {
            Remove-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        } catch {
            Write-Warning "Failed to remove image '$ImageId' in partition '$PartitionKey': $($_.Exception.Message)"
        }
    }
}

function Set-CIPPImageName {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Names a gallery image, so it can be picked by name wherever the image is offered.
    .DESCRIPTION
        Writes the name row Get-CIPPImageNameMap reads (PartitionKey imageMeta, RowKey the image id).
        An empty name removes the row, which reads back as "unnamed".
    .PARAMETER PartitionKey
        The image kind (logo, brandingCover).
    .PARAMETER Id
        The image's RowKey GUID.
    .PARAMETER Name
        The name to give it; blank to clear.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PartitionKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [AllowEmptyString()]
        [string]$Name = ''
    )

    $Table = Get-CIPPTable -TableName 'Images'
    $Entity = @{
        PartitionKey = 'imageMeta'
        RowKey       = $Id.Trim()
        kind         = $PartitionKey
        name         = $Name.Trim()
    }
    if (-not $PSCmdlet.ShouldProcess($Id, "Name image '$($Entity.name)'")) { return }
    if ([string]::IsNullOrWhiteSpace($Entity.name)) {
        try { Remove-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null } catch { Write-Warning "Failed to clear the name of image '$Id': $($_.Exception.Message)" }
        return
    }
    Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
}

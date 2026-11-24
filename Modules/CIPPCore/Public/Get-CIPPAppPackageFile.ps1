function Get-CIPPAppPackageFile {
    <#
    .SYNOPSIS
        Lists the files of uploaded app packages in the instance's own storage and the connected storage account
    .DESCRIPTION
        Returns PackageId, Name ('<packageId>/<file>'), Size, LastModified and Custom (stored in the connected
        account) for each file. Storage that cannot be listed writes an error; storage with no packages yet returns
        nothing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Current = Get-CIPPAppPackageStorage
    $Storages = @(
        @{ ConnectionString = $env:AzureWebJobsStorage; Custom = $false }
        if ($Current.Custom) { @{ ConnectionString = $Current.ConnectionString; Custom = $true } }
    )
    foreach ($Storage in $Storages) {
        $ListError = $null
        $Blobs = New-CIPPAzStorageRequest -Service blob -ConnectionString $Storage.ConnectionString -Resource 'app-packages' -QueryParams @{ restype = 'container'; comp = 'list' } -ErrorAction SilentlyContinue -ErrorVariable ListError
        if ($ListError -and "$ListError" -notmatch 'ContainerNotFound') { Write-Error -ErrorRecord $ListError[0] }
        foreach ($Blob in $Blobs) {
            [PSCustomObject]@{
                PackageId    = $Blob.Name.Split('/')[0]
                Name         = $Blob.Name
                Size         = [int64]$Blob.Properties['Content-Length']
                LastModified = $Blob.Properties['Last-Modified']
                Custom       = $Storage.Custom
            }
        }
    }
}

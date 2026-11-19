function Start-AppPackageCleanup {
    <#
    .SYNOPSIS
        Deletes uploaded app packages that no application template uses
    .DESCRIPTION
        Packages and installers uploaded for an application template that was never saved, or whose template
        was edited or deleted, stay in CIPP storage. Packages older than a day that no template references are
        deleted; newer ones may belong to a template still being created.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Blobs = @(New-CIPPAzStorageRequest -Service blob -Resource 'app-packages' -QueryParams @{ restype = 'container'; comp = 'list' } -ErrorAction SilentlyContinue)
    $Cutoff = [DateTime]::UtcNow.AddDays(-1)
    $PackageIds = @($Blobs.Where({ $_.Name -match '^[0-9a-fA-F-]{36}/' -and [DateTime]::Parse($_.Properties['Last-Modified']).ToUniversalTime() -lt $Cutoff }).ForEach({ ($_.Name -split '/')[0] }) | Select-Object -Unique)
    if ($PackageIds.Count -gt 0 -and $PSCmdlet.ShouldProcess("$($PackageIds.Count) app packages", 'Remove unused')) {
        Remove-CIPPUnusedAppPackage -PackageIds $PackageIds
    }
}

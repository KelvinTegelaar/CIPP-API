function Start-AppPackageCleanup {
    <#
    .SYNOPSIS
        Deletes uploaded app packages that no application template uses
    .DESCRIPTION
        Packages and installers uploaded for an application template that was never saved, or whose template
        was edited or deleted, stay in storage. Packages older than a day that no template references are
        deleted; newer ones may belong to a template still being created.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Files = @(Get-CIPPAppPackageFile -ErrorAction SilentlyContinue)
    $Cutoff = [DateTime]::UtcNow.AddDays(-1)
    $PackageIds = @($Files.Where({ $_.Name -match '^[0-9a-fA-F-]{36}/' -and [DateTime]::Parse($_.LastModified).ToUniversalTime() -lt $Cutoff }).PackageId | Select-Object -Unique)
    if ($PackageIds.Count -gt 0 -and $PSCmdlet.ShouldProcess("$($PackageIds.Count) app packages", 'Remove unused')) {
        Remove-CIPPUnusedAppPackage -PackageIds $PackageIds
    }
}

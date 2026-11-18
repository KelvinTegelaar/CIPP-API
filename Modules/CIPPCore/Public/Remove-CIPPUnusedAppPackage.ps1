function Remove-CIPPUnusedAppPackage {
    <#
    .SYNOPSIS
        Deletes uploaded .intunewin packages from CIPP storage once no application template references them.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string[]]$PackageIds
    )

    $Candidates = @(@($PackageIds).Where({ $_ }) | Select-Object -Unique)
    if ($Candidates.Count -eq 0) { return }
    $Table = Get-CIPPTable -TableName 'templates'
    $TemplateJson = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppTemplate'").JSON -join "`n"
    foreach ($PackageId in $Candidates) {
        if ($TemplateJson.Contains($PackageId) -or -not $PSCmdlet.ShouldProcess($PackageId, 'Remove app package')) { continue }
        foreach ($Blob in 'IntunePackage.intunewin', 'metadata.json') {
            $null = New-CIPPAzStorageRequest -Service blob -Resource "app-packages/$PackageId/$Blob" -Method DELETE -ErrorAction SilentlyContinue
        }
    }
}

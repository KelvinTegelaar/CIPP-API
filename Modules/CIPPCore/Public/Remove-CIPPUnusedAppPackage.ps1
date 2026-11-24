function Remove-CIPPUnusedAppPackage {
    <#
    .SYNOPSIS
        Deletes uploaded app packages from the storage they were uploaded to once no application template references them.
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
        try {
            $Storage = Get-CIPPAppPackageStorage -PackageId $PackageId
        } catch {
            Write-Information "Skipped app package $($PackageId): $($_.Exception.Message)"
            continue
        }
        foreach ($Blob in 'IntunePackage.intunewin', 'metadata.json', 'installer', 'packaged.json') {
            $null = New-CIPPAzStorageRequest -Service blob -ConnectionString $Storage.ConnectionString -Resource "app-packages/$PackageId/$Blob" -Method DELETE -ErrorAction SilentlyContinue
        }
        if ($Storage.Custom) {
            $PackagesTable = Get-CIPPTable -TableName 'AppPackages'
            Remove-CIPPAzDataTableEntity @PackagesTable -Entity @{ PartitionKey = 'AppPackage'; RowKey = $PackageId } -Force
        }
    }
}

function Get-CIPPAppPackageStorage {
    <#
    .SYNOPSIS
        Returns the storage account that holds uploaded app packages
    .DESCRIPTION
        Without PackageId: where new uploads go, a storage account connected in Settings or the instance's own
        storage. CyberDrain-hosted instances uploading to their own storage are limited to LimitBytes of packages
        (0 means no limit). With PackageId: where that package was uploaded. Packages uploaded to a connected account
        have a row in the AppPackages table, written by Invoke-ExecUploadAppPackage; the others are in the instance's
        own storage.
        The connected account is kept in the process environment (CIPP_APPPACKAGESTORAGE), shared by every worker,
        so only the first call after a start reads the table; Invoke-ExecAppPackageStorageConfig updates it on save.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$PackageId
    )

    if ($PackageId) {
        $PackagesTable = Get-CIPPTable -TableName 'AppPackages'
        $Package = Get-CIPPAzDataTableEntity @PackagesTable -Filter "PartitionKey eq 'AppPackage' and RowKey eq '$PackageId'"
        if (-not $Package) { return [PSCustomObject]@{ ConnectionString = $env:AzureWebJobsStorage; Custom = $false; AccountName = $null; LimitBytes = 0 } }
    }

    $Stored = [System.Environment]::GetEnvironmentVariable('CIPP_APPPACKAGESTORAGE')
    if (-not $Stored) {
        $Table = Get-CIPPTable -TableName Config
        $Settings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppPackageStorage' and RowKey eq 'Settings'"
        $Stored = if ($Settings.AccountName) { Get-ExtensionAPIKey -Extension 'AppPackageStorage' } else { 'default' }
        if (-not $Stored) { throw 'The connection string of the app package storage account could not be read from the key vault' }
        [System.Environment]::SetEnvironmentVariable('CIPP_APPPACKAGESTORAGE', $Stored)
    }
    $Custom = $Stored -ne 'default'
    $AccountName = if ($Custom -and $Stored -match '(?:^|;)\s*AccountName=([^;]+)') { $Matches[1] }
    if ($PackageId -and $Package.AccountName -ne $AccountName) {
        throw [System.Management.Automation.ItemNotFoundException]::new("This package is in storage account $($Package.AccountName), which is no longer connected to CIPP. Connect it again in Settings, or upload the package again.")
    }
    [PSCustomObject]@{
        ConnectionString = if ($Custom) { $Stored } else { $env:AzureWebJobsStorage }
        Custom           = $Custom
        AccountName      = $AccountName
        LimitBytes       = if (-not $PackageId -and -not $Custom -and [System.Environment]::GetEnvironmentVariable('CIPP_HOSTED') -eq 'true') { 10GB } else { 0 }
    }
}

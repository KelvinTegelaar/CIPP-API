function Invoke-ExecAppPackageStorageConfig {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Changes the storage account that holds uploaded app packages.
    .DESCRIPTION
        ConnectionString connects your own Azure storage account, which has no limit; Remove goes back to CIPP's own
        storage. New uploads go to the selected storage, and packages already uploaded keep working from where they
        are. A connected account cannot be disconnected or replaced while application templates use packages stored
        in it. ListAppPackageStorage shows the storage in use.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName Config
    $Filter = "PartitionKey eq 'AppPackageStorage' and RowKey eq 'Settings'"
    try {
        # True to disconnect the storage account and go back to CIPP's own storage
        $Remove = [bool]$Request.Body.Remove
        if (-not $Remove) {
            # Azure storage connection string with AccountName and AccountKey
            $ConnectionString = ([string]$Request.Body.ConnectionString).Trim()
            if ($ConnectionString -notmatch 'AccountKey=' -or $ConnectionString -notmatch '(?:^|;)\s*AccountName=([^;]+)') {
                throw [System.ArgumentException]::new('Enter a storage account connection string that includes AccountName and AccountKey, as shown under Access keys in the Azure portal.')
            }
            $AccountName = $Matches[1]
            try {
                $null = New-CIPPAzStorageRequest -Service blob -Component list -ConnectionString $ConnectionString -ErrorAction Stop
            } catch {
                throw [System.ArgumentException]::new("CIPP could not connect to storage account $($AccountName). Check that the connection string is current and that the storage account allows access from this instance.")
            }
        }

        $Settings = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if ($Settings.AccountName -and $Settings.AccountName -ne $AccountName) {
            $PackagesTable = Get-CIPPTable -TableName 'AppPackages'
            $Packages = @(Get-CIPPAzDataTableEntity @PackagesTable -Filter "PartitionKey eq 'AppPackage'")
            $TemplatesTable = Get-CIPPTable -TableName 'templates'
            $TemplateJson = (Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq 'AppTemplate'").JSON -join "`n"
            $InUse = $Packages.Where({ $TemplateJson.Contains($_.RowKey) }).Count
            if ($InUse) {
                throw [System.ArgumentException]::new("$InUse app package(s) used by application templates are stored in $($Settings.AccountName). Delete those templates, or remove the uploaded packages from them, before disconnecting this storage account.")
            }
            # Packages no template uses are left in their storage account, which CIPP no longer reaches
            if ($Packages.Count) { Remove-CIPPAzDataTableEntity @PackagesTable -Entity $Packages -Force }
        }

        if ($Remove) {
            $null = Remove-ExtensionAPIKey -Extension 'AppPackageStorage'
            if ($Settings) { Remove-CIPPAzDataTableEntity @Table -Entity $Settings -Force }
            [System.Environment]::SetEnvironmentVariable('CIPP_APPPACKAGESTORAGE', 'default')
            $Results = 'New app packages are now stored in CIPP storage'
        } else {
            $null = Set-ExtensionAPIKey -Extension 'AppPackageStorage' -APIKey $ConnectionString
            Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'AppPackageStorage'; RowKey = 'Settings'; AccountName = $AccountName } -Force
            [System.Environment]::SetEnvironmentVariable('CIPP_APPPACKAGESTORAGE', $ConnectionString)
            $Results = "New app packages are now stored in storage account $AccountName"
        }
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message $Results -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = "Failed to change app package storage: $($_.Exception.Message)"
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Results } })
}

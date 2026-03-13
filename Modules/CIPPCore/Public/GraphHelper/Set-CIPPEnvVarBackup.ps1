function Set-CIPPEnvVarBackup {
    param()

    $FunctionAppName = $env:WEBSITE_SITE_NAME
    $PropertiesToBackup = @(
        'AzureWebJobsStorage'
        'WEBSITE_RUN_FROM_PACKAGE'
        'FUNCTIONS_EXTENSION_VERSION'
        'FUNCTIONS_WORKER_RUNTIME'
        'CIPP_HOSTED'
        'CIPP_HOSTED_KV_SUB'
        'WEBSITE_ENABLE_SYNC_UPDATE_SITE'
        'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
    )

    $RequiredProperties = @('AzureWebJobsStorage', 'FUNCTIONS_EXTENSION_VERSION', 'FUNCTIONS_WORKER_RUNTIME', 'WEBSITE_RUN_FROM_PACKAGE')

    if ($env:WEBSITE_SKU -eq 'FlexConsumption') {
        $RequiredProperties = $RequiredProperties | Where-Object { $_ -ne 'WEBSITE_RUN_FROM_PACKAGE' }
    }

    $Backup = @{}
    foreach ($Property in $PropertiesToBackup) {
        $Backup[$Property] = [environment]::GetEnvironmentVariable($Property)
    }

    $EnvBackupTable = Get-CIPPTable -tablename 'EnvVarBackups'
    $CurrentBackup = Get-CIPPAzDataTableEntity @EnvBackupTable -Filter "PartitionKey eq 'EnvVarBackup' and RowKey eq '$FunctionAppName'"

    # ConvertFrom-Json returns PSCustomObject - convert to hashtable for consistent key/value access
    $CurrentValues = @{}
    if ($CurrentBackup -and $CurrentBackup.Values) {
        ($CurrentBackup.Values | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
            $CurrentValues[$_.Name] = $_.Value
        }
    }

    $IsNew = $CurrentValues.Count -eq 0

    if ($IsNew) {
        # First capture - write everything from the live environment
        $SavedValues = $Backup
        Write-Information "Creating new environment variable backup for $FunctionAppName"
    } else {
        # Backup already exists - keep existing values fixed, only backfill any properties not yet captured
        $SavedValues = $CurrentValues
        foreach ($Property in $PropertiesToBackup) {
            if (-not $SavedValues[$Property] -and $Backup[$Property]) {
                Write-Information "Backfilling missing backup property '$Property' from current environment."
                $SavedValues[$Property] = $Backup[$Property]
            }
        }
        Write-Information "Environment variable backup already exists for $FunctionAppName - preserving fixed values"
    }

    # Validate all required properties are present in the final backup
    $MissingRequired = $RequiredProperties | Where-Object { -not $SavedValues[$_] }
    if ($MissingRequired) {
        Write-Warning "Environment variable backup for $FunctionAppName is missing required properties: $($MissingRequired -join ', ')"
    }

    $Entity = @{
        PartitionKey = 'EnvVarBackup'
        RowKey       = $FunctionAppName
        Values       = [string]($SavedValues | ConvertTo-Json -Compress)
    }
    Add-CIPPAzDataTableEntity @EnvBackupTable -Entity $Entity -Force | Out-Null
}

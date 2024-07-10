function Push-CippExtensionData {
    param(
        $TenantFilter,
        $Extension
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Config = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop

    switch ($Extension) {
        'Hudu' {
            if ($Config.Hudu.Enabled) {
                Write-Host 'Perfoming Hudu Extension Sync...'
                Invoke-HuduExtensionSync -Configuration $Config.Hudu -TenantFilter $TenantFilter
            }
        }
    }
}

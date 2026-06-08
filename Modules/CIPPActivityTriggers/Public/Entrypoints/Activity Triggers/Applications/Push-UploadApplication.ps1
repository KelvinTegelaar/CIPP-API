function Push-UploadApplication {
    <#
        .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    try {
        $Table = Get-CippTable -tablename 'apps'
        $Filter = "PartitionKey eq 'apps' and RowKey eq '$($Item.Name)'"

        $AppConfig = (Get-CIPPAzDataTableEntity @Table -filter $Filter).JSON | ConvertFrom-Json
        $tenants = if ($AppConfig.tenant -eq 'AllTenants') {
            (Get-Tenants -IncludeErrors).defaultDomainName
        } else {
            $AppConfig.tenant
        }
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if ($AppConfig.tenant -ne 'AllTenants') {
            $null = Remove-AzDataTableEntity -Force @Table -Entity $clearRow
        } else {
            $Table.Force = $true
            $null = Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$($AppConfig | ConvertTo-Json)"
                RowKey       = "$($ClearRow.RowKey)"
                PartitionKey = 'apps'
                status       = 'Deployed'
            }
        }

        foreach ($tenant in $tenants) {
            try {
                $NewApp = New-CIPPIntuneAppDeployment -AppConfig $AppConfig -TenantFilter $tenant -APIName 'AppUpload'
            } catch {
                "Failed to add Application for $tenant : $($_.Exception.Message)"
                Write-LogMessage -api 'AppUpload' -tenant $tenant -message "Failed adding Application $($AppConfig.Applicationname). Error: $($_.Exception.Message)" -LogData (Get-CippException -Exception $_) -Sev 'Error'
                continue
            }
        }
    } catch {
        Write-Host "Error pushing application: $($_.Exception.Message)"
    }
}

function Push-GetTenants {
    Param($Item)

    $Params = $Item.TenantParams | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    try {
        Get-Tenants @Params | Select-Object customerId, @{n = 'FunctionName'; e = { $Item.DurableName } }
    } catch {
        Write-Host "GetTenants Exception $($_.Exception.Message)"
    }
}
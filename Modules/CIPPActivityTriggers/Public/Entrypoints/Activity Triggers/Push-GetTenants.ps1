function Push-GetTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    Param($Item)

    $Params = $Item.TenantParams | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    try {
        if ($Item.QueueId) {
            Get-Tenants @Params | Select-Object customerId, @{n = 'FunctionName'; e = { $Item.DurableName } }, @{n = 'QueueId'; e = { $Item.QueueId } }, @{n = 'QueueName'; e = { $_.defaultDomainName } }
        } else {
            Get-Tenants @Params | Select-Object customerId, @{n = 'FunctionName'; e = { $Item.DurableName } }
        }
    } catch {
        Write-Host "GetTenants Exception $($_.Exception.Message)"
    }
}
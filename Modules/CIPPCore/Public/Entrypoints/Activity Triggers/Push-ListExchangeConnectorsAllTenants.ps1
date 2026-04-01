function Push-ListExchangeConnectorsAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheExchangeConnectors

    try {
        $Connectors = @()
        $Connectors += New-ExoRequest -tenantid $DomainName -cmdlet 'Get-OutboundConnector' | Select-Object *, @{n = 'cippconnectortype'; e = { 'outbound' } }
        $Connectors += New-ExoRequest -tenantid $DomainName -cmdlet 'Get-InboundConnector' | Select-Object *, @{n = 'cippconnectortype'; e = { 'Inbound' } }

        foreach ($Item in $Connectors) {
            $GUID = (New-Guid).Guid
            $PolicyData = $Item | Select-Object *, @{n = 'Tenant'; e = { $DomainName } }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'ExchangeConnector'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant      = $DomainName
            Name        = "Could not connect to Tenant: $($_.Exception.Message)"
            id          = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'ExchangeConnector'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}

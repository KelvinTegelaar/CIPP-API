function Push-ListTransportRulesAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheTransportRules

    try {
        $TransportRules = New-ExoRequest -tenantid $DomainName -cmdlet 'Get-TransportRule'
        $Results = foreach ($rule in $TransportRules) {
            $GUID = (New-Guid).Guid
            $Results = @{
                TransportRule = [string]($rule | ConvertTo-Json -Depth 10)
                RowKey        = [string]$GUID
                PartitionKey  = 'TransportRule'
                Tenant        = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Results -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorText = ConvertTo-Json -InputObject @{
            Tenant      = $DomainName
            Name        = "Could not connect to Tenant: $($_.Exception.Message)"
            State       = 'Error'
            Priority    = 0
            Description = "Error retrieving transport rules: $($_.Exception.Message)"
        }
        $Results = @{
            TransportRule = [string]$ErrorText
            RowKey        = [string]$GUID
            PartitionKey  = 'TransportRule'
            Tenant        = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Results -Force | Out-Null
    }
}

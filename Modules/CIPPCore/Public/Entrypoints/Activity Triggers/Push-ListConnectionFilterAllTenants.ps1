function Push-ListConnectionFilterAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheConnectionFilter

    try {
        $Policies = New-ExoRequest -tenantid $DomainName -cmdlet 'Get-HostedConnectionFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*

        foreach ($Item in $Policies) {
            $GUID = (New-Guid).Guid
            $PolicyData = $Item | Select-Object *, @{n = 'Tenant'; e = { $DomainName } }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'ConnectionFilter'
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
            PartitionKey = 'ConnectionFilter'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}

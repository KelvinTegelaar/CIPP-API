function Push-ListAntiPhishingFiltersAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheAntiPhishingFilters

    try {
        $Policies = New-ExoRequest -tenantid $DomainName -cmdlet 'Get-AntiPhishPolicy' | Select-Object -Property *
        $Rules = New-ExoRequest -tenantid $DomainName -cmdlet 'Get-AntiPhishRule' | Select-Object -Property *

        $Output = $Policies | Select-Object -Property *,
        @{ Name = 'RuleName'; Expression = { foreach ($item in $Rules) { if ($item.AntiPhishPolicy -eq $_.Name) { $item.Name } } } },
        @{ Name = 'Priority'; Expression = { foreach ($item in $Rules) { if ($item.AntiPhishPolicy -eq $_.Name) { $item.Priority } } } },
        @{ Name = 'RecipientDomainIs'; Expression = { foreach ($item in $Rules) { if ($item.AntiPhishPolicy -eq $_.Name) { $item.RecipientDomainIs } } } },
        @{ Name = 'State'; Expression = { foreach ($item in $Rules) { if ($item.AntiPhishPolicy -eq $_.Name) { $item.State } } } }

        foreach ($Item in $Output) {
            $GUID = (New-Guid).Guid
            $PolicyData = $Item | Select-Object *, @{n = 'Tenant'; e = { $DomainName } }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'AntiPhishingFilter'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant      = $DomainName
            RuleName    = "Could not connect to Tenant: $($_.Exception.Message)"
            Name        = 'Error'
            id          = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'AntiPhishingFilter'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}

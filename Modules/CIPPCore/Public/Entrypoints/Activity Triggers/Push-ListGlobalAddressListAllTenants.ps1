function Push-ListGlobalAddressListAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheGlobalAddressList

    try {
        $GAL = New-ExoRequest -tenantid $DomainName -cmdlet 'Get-Recipient' -cmdParams @{ResultSize = 'unlimited'; SortBy = 'DisplayName' } `
            -Select 'Identity, DisplayName, Alias, PrimarySmtpAddress, ExternalDirectoryObjectId, HiddenFromAddressListsEnabled, EmailAddresses, IsDirSynced, SKUAssigned, RecipientType, RecipientTypeDetails, AddressListMembership' |
            Select-Object -ExcludeProperty *odata*, *data.type*

        foreach ($Item in $GAL) {
            $GUID = (New-Guid).Guid
            $PolicyData = [PSCustomObject]@{
                Identity                       = $Item.Identity
                DisplayName                    = $Item.DisplayName
                Alias                          = $Item.Alias
                PrimarySmtpAddress             = $Item.PrimarySmtpAddress
                ExternalDirectoryObjectId      = $Item.ExternalDirectoryObjectId
                HiddenFromAddressListsEnabled  = $Item.HiddenFromAddressListsEnabled
                EmailAddresses                 = $Item.EmailAddresses
                IsDirSynced                    = $Item.IsDirSynced
                SKUAssigned                    = $Item.SKUAssigned
                RecipientType                  = $Item.RecipientType
                RecipientTypeDetails           = $Item.RecipientTypeDetails
                AddressListMembership          = $Item.AddressListMembership
                Tenant                         = $DomainName
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'GlobalAddressList'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant      = $DomainName
            DisplayName = "Could not connect to Tenant: $($_.Exception.Message)"
            id          = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'GlobalAddressList'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}

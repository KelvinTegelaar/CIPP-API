function Push-ListRoomListsAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheRoomLists

    try {
        $RoomLists = New-ExoRequest -tenantid $DomainName -cmdlet 'Get-DistributionGroup' -cmdParams @{
            RecipientTypeDetails = 'RoomList'
            ResultSize           = 'Unlimited'
        } | Select-Object Guid, DisplayName, PrimarySmtpAddress, Alias, Phone, Identity, Notes, Description, Id -ExcludeProperty *data.type*

        foreach ($Item in $RoomLists) {
            $GUID = (New-Guid).Guid
            $PolicyData = [PSCustomObject]@{
                Guid               = $Item.Guid
                DisplayName        = $Item.DisplayName
                PrimarySmtpAddress = $Item.PrimarySmtpAddress
                Alias              = $Item.Alias
                Phone              = $Item.Phone
                Identity           = $Item.Identity
                Notes              = $Item.Notes
                Description        = $Item.Description
                MailNickname       = $Item.Alias
                Tenant             = $DomainName
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'RoomList'
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
            PartitionKey = 'RoomList'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}

function Push-ListRoomsAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheRooms

    try {
        $RoomMailboxes = New-ExoRequest -tenantid $DomainName -cmdlet 'Get-Mailbox' -cmdParams @{
            RecipientTypeDetails = 'RoomMailbox'
            ResultSize           = 'Unlimited'
        } | Select-Object -ExcludeProperty *@odata.type*

        $Places = New-ExoRequest -tenantid $DomainName -cmdlet 'Get-Place' -cmdParams @{
            ResultSize = 'Unlimited'
        } | Select-Object -ExcludeProperty *@odata.type*

        $PlacesLookup = @{}
        foreach ($Place in $Places) {
            if ($Place.Identity) {
                $PlacesLookup[$Place.Identity] = $Place
            }
        }

        foreach ($Room in $RoomMailboxes) {
            $PlaceDetails = $PlacesLookup[$Room.UserPrincipalName] ?? $PlacesLookup[$Room.PrimarySmtpAddress]
            $GUID = (New-Guid).Guid
            $PolicyData = [PSCustomObject]@{
                id                            = $Room.ExternalDirectoryObjectId
                displayName                   = $Room.DisplayName
                mail                          = $Room.PrimarySmtpAddress
                mailNickname                  = $Room.Alias
                accountDisabled               = $Room.AccountDisabled
                hiddenFromAddressListsEnabled = $Room.HiddenFromAddressListsEnabled
                isDirSynced                   = $Room.IsDirSynced
                bookingType                   = $PlaceDetails.BookingType
                resourceDelegates             = $PlaceDetails.ResourceDelegates
                capacity                      = [int]($PlaceDetails.Capacity ?? $Room.ResourceCapacity ?? 0)
                building                      = $PlaceDetails.Building
                floor                         = $PlaceDetails.Floor
                floorLabel                    = $PlaceDetails.FloorLabel
                street                        = if ([string]::IsNullOrWhiteSpace($PlaceDetails.Street)) { $null } else { $PlaceDetails.Street }
                city                          = if ([string]::IsNullOrWhiteSpace($PlaceDetails.City)) { $null } else { $PlaceDetails.City }
                state                         = if ([string]::IsNullOrWhiteSpace($PlaceDetails.State)) { $null } else { $PlaceDetails.State }
                postalCode                    = if ([string]::IsNullOrWhiteSpace($PlaceDetails.PostalCode)) { $null } else { $PlaceDetails.PostalCode }
                countryOrRegion               = if ([string]::IsNullOrWhiteSpace($PlaceDetails.CountryOrRegion)) { $null } else { $PlaceDetails.CountryOrRegion }
                audioDeviceName               = $PlaceDetails.AudioDeviceName
                videoDeviceName               = $PlaceDetails.VideoDeviceName
                displayDeviceName             = $PlaceDetails.DisplayDeviceName
                mtrEnabled                    = $PlaceDetails.MTREnabled
                isWheelChairAccessible        = $PlaceDetails.IsWheelChairAccessible
                phone                         = if ([string]::IsNullOrWhiteSpace($PlaceDetails.Phone)) { $null } else { $PlaceDetails.Phone }
                tags                          = $PlaceDetails.Tags
                spaceType                     = $PlaceDetails.SpaceType
                Tenant                        = $DomainName
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'Room'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant      = $DomainName
            displayName = "Could not connect to Tenant: $($_.Exception.Message)"
            id          = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'Room'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}

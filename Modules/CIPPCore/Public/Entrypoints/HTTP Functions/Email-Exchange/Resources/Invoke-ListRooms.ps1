Function Invoke-ListRooms {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Room.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $RoomId = $Request.Query.roomId

    # I dont like that i had to change it to EXO commands, but the waiting time for the Rooms to sync to Graph is too long :(  -Bobby
    try {
        if ($RoomId) {
            # Get specific room mailbox
            $RoomMailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{
                Identity             = $RoomId
                RecipientTypeDetails = 'RoomMailbox'
            } | Select-Object -ExcludeProperty *@odata.type*

            # Get place details
            $PlaceDetails = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Place' -cmdParams @{
                Identity = $RoomId
            } | Select-Object -ExcludeProperty *@odata.type*

            # Get calendar properties
            $CalendarProperties = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CalendarProcessing' -cmdParams @{
                Identity = $RoomId
            } | Select-Object -ExcludeProperty *@odata.type*

            # Get calendar properties
            $CalendarConfigurationProperties = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxCalendarConfiguration' -cmdParams @{
                Identity = $RoomId
            } | Select-Object -ExcludeProperty *@odata.type*

            if ($RoomMailbox -and $PlaceDetails -and $CalendarProperties -and $CalendarConfigurationProperties) {
                $GraphRequest = @(
                    [PSCustomObject]@{
                        # Core Mailbox Properties
                        id                             = $RoomMailbox.ExternalDirectoryObjectId
                        displayName                    = $RoomMailbox.DisplayName
                        mail                           = $RoomMailbox.PrimarySmtpAddress
                        mailNickname                   = $RoomMailbox.Alias
                        accountDisabled                = $RoomMailbox.AccountDisabled
                        hiddenFromAddressListsEnabled  = $RoomMailbox.HiddenFromAddressListsEnabled
                        isDirSynced                    = $RoomMailbox.IsDirSynced

                        # Room Booking Settings
                        bookingType                    = $PlaceDetails.BookingType
                        resourceDelegates              = $PlaceDetails.ResourceDelegates
                        capacity                       = [int]($PlaceDetails.Capacity ?? $RoomMailbox.ResourceCapacity ?? 0)

                        # Location Information
                        building                       = $PlaceDetails.Building
                        floor                          = $PlaceDetails.Floor
                        floorLabel                     = $PlaceDetails.FloorLabel
                        street                         = if ([string]::IsNullOrWhiteSpace($PlaceDetails.Street)) { $null } else { $PlaceDetails.Street }
                        city                           = if ([string]::IsNullOrWhiteSpace($PlaceDetails.City)) { $null } else { $PlaceDetails.City }
                        state                          = if ([string]::IsNullOrWhiteSpace($PlaceDetails.State)) { $null } else { $PlaceDetails.State }
                        postalCode                     = if ([string]::IsNullOrWhiteSpace($PlaceDetails.PostalCode)) { $null } else { $PlaceDetails.PostalCode }
                        countryOrRegion                = if ([string]::IsNullOrWhiteSpace($PlaceDetails.CountryOrRegion)) { $null } else { $PlaceDetails.CountryOrRegion }

                        # Room Equipment
                        audioDeviceName                = $PlaceDetails.AudioDeviceName
                        videoDeviceName                = $PlaceDetails.VideoDeviceName
                        displayDeviceName              = $PlaceDetails.DisplayDeviceName
                        mtrEnabled                     = $PlaceDetails.MTREnabled

                        # Room Features
                        isWheelChairAccessible         = $PlaceDetails.IsWheelChairAccessible
                        phone                          = if ([string]::IsNullOrWhiteSpace($PlaceDetails.Phone)) { $null } else { $PlaceDetails.Phone }
                        tags                           = $PlaceDetails.Tags
                        spaceType                      = $PlaceDetails.SpaceType

                        # Calendar Properties
                        AllowConflicts                 = $CalendarProperties.AllowConflicts
                        AllowRecurringMeetings         = $CalendarProperties.AllowRecurringMeetings
                        BookingWindowInDays            = $CalendarProperties.BookingWindowInDays
                        MaximumDurationInMinutes       = $CalendarProperties.MaximumDurationInMinutes
                        ProcessExternalMeetingMessages = $CalendarProperties.ProcessExternalMeetingMessages
                        EnforceCapacity                = $CalendarProperties.EnforceCapacity
                        ForwardRequestsToDelegates     = $CalendarProperties.ForwardRequestsToDelegates
                        ScheduleOnlyDuringWorkHours    = $CalendarProperties.ScheduleOnlyDuringWorkHours
                        AutomateProcessing             = $CalendarProperties.AutomateProcessing
                        AddOrganizerToSubject          = $CalendarProperties.AddOrganizerToSubject
                        DeleteSubject                  = $CalendarProperties.DeleteSubject
                        RemoveCanceledMeetings         = $CalendarProperties.RemoveCanceledMeetings

                        # Calendar Configuration Properties
                        WorkDays                       = if ([string]::IsNullOrWhiteSpace($CalendarConfigurationProperties.WorkDays)) { $null } else { $CalendarConfigurationProperties.WorkDays }
                        WorkHoursStartTime             = if ([string]::IsNullOrWhiteSpace($CalendarConfigurationProperties.WorkHoursStartTime)) { $null } else { $CalendarConfigurationProperties.WorkHoursStartTime }
                        WorkHoursEndTime               = if ([string]::IsNullOrWhiteSpace($CalendarConfigurationProperties.WorkHoursEndTime)) { $null } else { $CalendarConfigurationProperties.WorkHoursEndTime }
                        WorkingHoursTimeZone           = $CalendarConfigurationProperties.WorkingHoursTimeZone
                    }
                )
            }
        } else {
            # Get all room mailboxes in one call
            $RoomMailboxes = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{
                RecipientTypeDetails = 'RoomMailbox'
                ResultSize           = 'Unlimited'
            } | Select-Object -ExcludeProperty *@odata.type*

            # Get all places in one call
            $Places = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Place' -cmdParams @{
                ResultSize = 'Unlimited'
            } | Select-Object -ExcludeProperty *@odata.type*

            # Create hashtable for quick place lookups
            $PlacesLookup = @{}
            foreach ($Place in $Places) {
                if ($Place.Identity) {
                    $PlacesLookup[$Place.Identity] = $Place
                }
            }

            $GraphRequest = @(
                foreach ($Room in $RoomMailboxes) {
                    $PlaceDetails = $PlacesLookup[$Room.UserPrincipalName] ?? $PlacesLookup[$Room.PrimarySmtpAddress]

                    [PSCustomObject]@{
                        # Core Mailbox Properties
                        id                            = $Room.ExternalDirectoryObjectId
                        displayName                   = $Room.DisplayName
                        mail                          = $Room.PrimarySmtpAddress
                        mailNickname                  = $Room.Alias
                        accountDisabled               = $Room.AccountDisabled
                        hiddenFromAddressListsEnabled = $Room.HiddenFromAddressListsEnabled
                        isDirSynced                   = $RoomMailbox.IsDirSynced

                        # Room Booking Settings
                        bookingType                   = $PlaceDetails.BookingType
                        resourceDelegates             = $PlaceDetails.ResourceDelegates
                        capacity                      = [int]($PlaceDetails.Capacity ?? $Room.ResourceCapacity ?? 0)

                        # Location Information
                        building                      = $PlaceDetails.Building
                        floor                         = $PlaceDetails.Floor
                        floorLabel                    = $PlaceDetails.FloorLabel
                        street                        = if ([string]::IsNullOrWhiteSpace($PlaceDetails.Street)) { $null } else { $PlaceDetails.Street }
                        city                          = if ([string]::IsNullOrWhiteSpace($PlaceDetails.City)) { $null } else { $PlaceDetails.City }
                        state                         = if ([string]::IsNullOrWhiteSpace($PlaceDetails.State)) { $null } else { $PlaceDetails.State }
                        postalCode                    = if ([string]::IsNullOrWhiteSpace($PlaceDetails.PostalCode)) { $null } else { $PlaceDetails.PostalCode }
                        countryOrRegion               = if ([string]::IsNullOrWhiteSpace($PlaceDetails.CountryOrRegion)) { $null } else { $PlaceDetails.CountryOrRegion }


                        # Room Equipment
                        audioDeviceName               = $PlaceDetails.AudioDeviceName
                        videoDeviceName               = $PlaceDetails.VideoDeviceName
                        displayDeviceName             = $PlaceDetails.DisplayDeviceName
                        mtrEnabled                    = $PlaceDetails.MTREnabled

                        # Room Features
                        isWheelChairAccessible        = $PlaceDetails.IsWheelChairAccessible
                        phone                         = if ([string]::IsNullOrWhiteSpace($PlaceDetails.Phone)) { $null } else { $PlaceDetails.Phone }
                        tags                          = $PlaceDetails.Tags
                        spaceType                     = $PlaceDetails.SpaceType
                    }
                }
            )
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Sort-Object displayName)
        })
}

function Invoke-ListRooms {
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
            # Batch mailbox, place, and calendar processing together
            $BulkBatch = @(
                @{ CmdletInput = @{ CmdletName = 'Get-Mailbox'; Parameters = @{ Identity = $RoomId; RecipientTypeDetails = 'RoomMailbox' } } }
                @{ CmdletInput = @{ CmdletName = 'Get-Place'; Parameters = @{ Identity = $RoomId } } }
                @{ CmdletInput = @{ CmdletName = 'Get-CalendarProcessing'; Parameters = @{ Identity = $RoomId } } }
            )
            $BulkResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $BulkBatch -ReturnWithCommand $true

            $RoomMailbox = $BulkResults['Get-Mailbox'] | Select-Object -ExcludeProperty *@odata.type* | Select-Object -First 1
            $PlaceDetails = $BulkResults['Get-Place'] | Select-Object -ExcludeProperty *@odata.type* | Select-Object -First 1
            $CalendarProperties = $BulkResults['Get-CalendarProcessing'] | Select-Object -ExcludeProperty *@odata.type* | Select-Object -First 1

            # Get-MailboxCalendarConfiguration requires anchor to the room mailbox
            $CalendarConfigurationProperties = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxCalendarConfiguration' -cmdParams @{ Identity = $RoomId } -Anchor $RoomId | Select-Object -ExcludeProperty *@odata.type*

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
            # Batch Get-Mailbox and Get-Place into one request
            $CmdletArray = @(
                @{ CmdletInput = @{ CmdletName = 'Get-Mailbox'; Parameters = @{ RecipientTypeDetails = 'RoomMailbox'; ResultSize = 'Unlimited' } } }
                @{ CmdletInput = @{ CmdletName = 'Get-Place'; Parameters = @{ ResultSize = 'Unlimited' } } }
            )
            $BulkResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $CmdletArray -ReturnWithCommand $true

            $RoomMailboxes = $BulkResults['Get-Mailbox'] | Select-Object -ExcludeProperty *@odata.type*
            $Places = $BulkResults['Get-Place'] | Select-Object -ExcludeProperty *@odata.type*

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

Function Invoke-EditRoomMailbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Room.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Tenant = $Request.Body.tenantID


    $Results = [System.Collections.Generic.List[Object]]::new()
    $MailboxObject = $Request.Body
    $DefaultCalendarPermission = $MailboxObject.DefaultCalendarPermission.value ?? $MailboxObject.DefaultCalendarPermission

    # First update the mailbox properties
    $UpdateMailboxParams = @{
        Identity    = $MailboxObject.roomId
        DisplayName = $MailboxObject.displayName
    }

    if (![string]::IsNullOrWhiteSpace($MailboxObject.capacity)) {
        $UpdateMailboxParams.Add('ResourceCapacity', $MailboxObject.capacity)
    }
    if (![string]::IsNullOrWhiteSpace($MailboxObject.hiddenFromAddressListsEnabled)) {
        $UpdateMailboxParams.Add('HiddenFromAddressListsEnabled', $MailboxObject.hiddenFromAddressListsEnabled)
    }


    # Then update the place properties
    $UpdatePlaceParams = @{
        Identity = $MailboxObject.roomId
    }

    # Add optional parameters if they exist
    $PlaceProperties = @(
        'Building', 'Floor', 'FloorLabel', 'Phone',
        'AudioDeviceName', 'VideoDeviceName', 'DisplayDeviceName',
        'IsWheelChairAccessible', 'Tags',
        'Street', 'City', 'State', 'CountryOrRegion', 'Desks',
        'PostalCode', 'Localities', 'SpaceType', 'CustomSpaceType',
        'ResourceLinks'
    )

    foreach ($prop in $PlaceProperties) {
        if (![string]::IsNullOrWhiteSpace($MailboxObject.$prop)) {
            $UpdatePlaceParams[$prop] = $MailboxObject.$prop
        }
    }


    # Then update the calendar properties
    $UpdateCalendarParams = @{
        Identity = $MailboxObject.roomId
    }

    $CalendarProperties = @(
        'AllowConflicts', 'AllowRecurringMeetings', 'BookingWindowInDays',
        'MaximumDurationInMinutes', 'ProcessExternalMeetingMessages', 'EnforceCapacity',
        'ForwardRequestsToDelegates', 'ScheduleOnlyDuringWorkHours', 'AutomateProcessing',
        'AddOrganizerToSubject', 'DeleteComments', 'DeleteSubject', 'RemovePrivateProperty',
        'RemoveCanceledMeetings', 'RemoveOldMeetingMessages'
    )

    foreach ($prop in $CalendarProperties) {
        if (![string]::IsNullOrWhiteSpace($MailboxObject.$prop)) {
            $UpdateCalendarParams[$prop] = $MailboxObject.$prop
        }
    }

    # Then update the calendar configuration
    $UpdateCalendarConfigParams = @{
        Identity = $MailboxObject.roomId
    }

    $CalendarConfiguration = @(
        'WorkDays', 'WorkHoursStartTime', 'WorkHoursEndTime', 'WorkingHoursTimeZone'
    )

    foreach ($prop in $CalendarConfiguration) {
        if (![string]::IsNullOrWhiteSpace($MailboxObject.$prop)) {
            $UpdateCalendarConfigParams[$prop] = $MailboxObject.$prop
        }
    }

    try {
        # Batch mailbox, place, and calendar processing together
        $BulkBatch = @(
            @{ CmdletInput = @{ CmdletName = 'Set-Mailbox'; Parameters = $UpdateMailboxParams } }
            @{ CmdletInput = @{ CmdletName = 'Set-Place'; Parameters = $UpdatePlaceParams } }
            @{ CmdletInput = @{ CmdletName = 'Set-CalendarProcessing'; Parameters = $UpdateCalendarParams } }
        )
        $null = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $BulkBatch
        $Results.Add("Successfully updated room: $($MailboxObject.DisplayName) (Mailbox, Place & Calendar Properties)")

        # Set-MailboxCalendarConfiguration requires anchor to the room mailbox
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxCalendarConfiguration' -cmdParams $UpdateCalendarConfigParams -Anchor $MailboxObject.roomId
        $Results.Add("Successfully updated room: $($MailboxObject.DisplayName) (Calendar Configuration)")

        if (![string]::IsNullOrWhiteSpace($DefaultCalendarPermission)) {
            $CalendarFolder = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxFolderStatistics' -cmdParams @{
                Identity    = $MailboxObject.roomId
                FolderScope = 'Calendar'
            } -Anchor $MailboxObject.roomId | Where-Object { $_.FolderType -eq 'Calendar' } | Select-Object -First 1 -ExcludeProperty *@odata.type*

            $CalendarFolderIdentity = if ($CalendarFolder -and $CalendarFolder.FolderId) {
                "$($MailboxObject.roomId):$($CalendarFolder.FolderId)"
            } elseif ($CalendarFolder -and $CalendarFolder.Name) {
                "$($MailboxObject.roomId):\$($CalendarFolder.Name)"
            } else {
                "$($MailboxObject.roomId):\Calendar"
            }

            $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxFolderPermission' -cmdParams @{
                Identity     = $CalendarFolderIdentity
                User         = 'Default'
                AccessRights = $DefaultCalendarPermission
            } -Anchor $MailboxObject.roomId

            Sync-CIPPCalendarPermissionCache -TenantFilter $Tenant -MailboxIdentity $MailboxObject.roomId -FolderName 'Calendar' -User 'Default' -Permissions $DefaultCalendarPermission -Action 'Add'
            $Results.Add("Successfully updated room: $($MailboxObject.DisplayName) (Default Calendar Permission)")
        }

        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Tenant -message "Updated room $($MailboxObject.DisplayName)" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Tenant -message "Failed to update room: $($MailboxObject.DisplayName). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results.Add("Failed to update Room mailbox $($MailboxObject.userPrincipalName). $($ErrorMessage.NormalizedError)")

        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $Body = [pscustomobject]@{ 'Results' = @($Results) }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

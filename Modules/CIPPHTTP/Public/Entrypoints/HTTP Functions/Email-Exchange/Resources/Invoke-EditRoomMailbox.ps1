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
        'ForwardRequestsToDelegates', 'ScheduleOnlyDuringWorkHours ', 'AutomateProcessing'
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
        # Update mailbox properties
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Mailbox' -cmdParams $UpdateMailboxParams

        # Update place properties
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Place' -cmdParams $UpdatePlaceParams
        $Results.Add("Successfully updated room: $($MailboxObject.DisplayName) (Place Properties)")

        # Update calendar properties
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-CalendarProcessing' -cmdParams $UpdateCalendarParams
        $Results.Add("Successfully updated room: $($MailboxObject.DisplayName) (Calendar Properties)")

        # Update calendar configuration properties
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxCalendarConfiguration' -cmdParams $UpdateCalendarConfigParams
        $Results.Add("Successfully updated room: $($MailboxObject.DisplayName) (Calendar Configuration)")

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

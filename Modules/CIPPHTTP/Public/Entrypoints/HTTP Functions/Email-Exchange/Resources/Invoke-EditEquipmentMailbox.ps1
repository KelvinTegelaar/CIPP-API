Function Invoke-EditEquipmentMailbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Equipment.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Tenant = $Request.Body.tenantID

    $Results = [System.Collections.Generic.List[Object]]::new()
    $MailboxObject = $Request.Body

    # First update the mailbox properties
    $UpdateMailboxParams = @{
        Identity    = $MailboxObject.equipmentId
        DisplayName = $MailboxObject.displayName
    }

    if (![string]::IsNullOrWhiteSpace($MailboxObject.hiddenFromAddressListsEnabled)) {
        $UpdateMailboxParams.Add('HiddenFromAddressListsEnabled', $MailboxObject.hiddenFromAddressListsEnabled)
    }

    # Then update the user properties
    $UpdateUserParams = @{
        Identity = $MailboxObject.equipmentId
    }

    # Add optional parameters if they exist
    $UserProperties = @(
        'Location', 'Department', 'Company',
        'Phone', 'Tags',
        'StreetAddress', 'City', 'StateOrProvince', 'CountryOrRegion',
        'PostalCode'
    )

    foreach ($prop in $UserProperties) {
        if (![string]::IsNullOrWhiteSpace($MailboxObject.$prop)) {
            $UpdateUserParams[$prop] = $MailboxObject.$prop
        }
    }

    # Then update the calendar properties
    $UpdateCalendarParams = @{
        Identity = $MailboxObject.equipmentId
    }

    $CalendarProperties = @(
        'AllowConflicts', 'AllowRecurringMeetings', 'BookingWindowInDays',
        'MaximumDurationInMinutes', 'ProcessExternalMeetingMessages',
        'ForwardRequestsToDelegates', 'ScheduleOnlyDuringWorkHours', 'AutomateProcessing'
    )

    foreach ($prop in $CalendarProperties) {
        if (![string]::IsNullOrWhiteSpace($MailboxObject.$prop)) {
            $UpdateCalendarParams[$prop] = $MailboxObject.$prop
        }
    }

    # Then update the calendar configuration
    $UpdateCalendarConfigParams = @{
        Identity = $MailboxObject.equipmentId
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

        # Update user properties
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-User' -cmdParams $UpdateUserParams
        $Results.Add("Successfully updated equipment: $($MailboxObject.DisplayName) (User Properties)")

        # Update calendar properties
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-CalendarProcessing' -cmdParams $UpdateCalendarParams
        $Results.Add("Successfully updated equipment: $($MailboxObject.DisplayName) (Calendar Properties)")

        # Update calendar configuration properties
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxCalendarConfiguration' -cmdParams $UpdateCalendarConfigParams
        $Results.Add("Successfully updated equipment: $($MailboxObject.DisplayName) (Calendar Configuration)")

        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Updated equipment $($MailboxObject.DisplayName)" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Failed to update equipment: $($MailboxObject.DisplayName). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results.Add("Failed to update Equipment mailbox $($MailboxObject.userPrincipalName). $($ErrorMessage.NormalizedError)")
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $Body = [pscustomobject]@{ 'Results' = @($Results) }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

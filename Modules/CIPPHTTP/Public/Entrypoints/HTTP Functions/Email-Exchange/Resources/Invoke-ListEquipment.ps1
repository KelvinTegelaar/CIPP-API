function Invoke-ListEquipment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Equipment.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $EquipmentId = $Request.Query.EquipmentId
    $Tenant = $Request.Query.TenantFilter

    try {
        if ($EquipmentId) {
            # Get specific equipment details
            $Equipment = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{
                Identity             = $EquipmentId
                RecipientTypeDetails = 'EquipmentMailbox'
            }

            $UserDetails = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-User' -cmdParams @{
                Identity = $EquipmentId
            }

            $CalendarProcessing = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-CalendarProcessing' -cmdParams @{
                Identity = $EquipmentId
            }

            $CalendarConfig = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxCalendarConfiguration' -cmdParams @{
                Identity = $EquipmentId
            }

            $Results = [PSCustomObject]@{
                # Core mailbox properties
                displayName                    = $Equipment.DisplayName
                hiddenFromAddressListsEnabled  = $Equipment.HiddenFromAddressListsEnabled
                userPrincipalName              = $Equipment.UserPrincipalName
                primarySmtpAddress             = $Equipment.PrimarySmtpAddress

                # Equipment details from Get-User
                department                     = $UserDetails.Department
                company                        = $UserDetails.Company

                # Location information from Get-User
                street                         = $UserDetails.Street
                city                           = $UserDetails.City
                state                          = $UserDetails.State
                postalCode                     = $UserDetails.PostalCode
                countryOrRegion                = $UserDetails.CountryOrRegion

                # Equipment features
                phone                          = $UserDetails.Phone
                tags                           = $UserDetails.Tags

                # Calendar properties from Get-CalendarProcessing
                allowConflicts                 = $CalendarProcessing.AllowConflicts
                allowRecurringMeetings         = $CalendarProcessing.AllowRecurringMeetings
                bookingWindowInDays            = $CalendarProcessing.BookingWindowInDays
                maximumDurationInMinutes       = $CalendarProcessing.MaximumDurationInMinutes
                processExternalMeetingMessages = $CalendarProcessing.ProcessExternalMeetingMessages
                forwardRequestsToDelegates     = $CalendarProcessing.ForwardRequestsToDelegates
                scheduleOnlyDuringWorkHours    = $CalendarProcessing.ScheduleOnlyDuringWorkHours
                automateProcessing             = $CalendarProcessing.AutomateProcessing

                # Calendar configuration from Get-MailboxCalendarConfiguration
                workDays                       = $CalendarConfig.WorkDays
                workHoursStartTime             = $CalendarConfig.WorkHoursStartTime
                workHoursEndTime               = $CalendarConfig.WorkHoursEndTime
                workingHoursTimeZone           = $CalendarConfig.WorkingHoursTimeZone
            }
        } else {
            # List all equipment mailboxes
            $Results = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{
                RecipientTypeDetails = 'EquipmentMailbox'
                ResultSize           = 'Unlimited'
            } | Select-Object -ExcludeProperty *data.type*
        }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Results = $ErrorMessage
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results | Sort-Object displayName)
        })
}

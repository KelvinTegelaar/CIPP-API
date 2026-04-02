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
        if ($Tenant -eq 'AllTenants' -and !$EquipmentId) {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName CacheEquipment
            $PartitionKey = 'Equipment'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
            $QueueReference = '{0}-{1}' -f $Tenant, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading equipment for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Equipment - All Tenants' -Link '/email/resources/management/equipment?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading equipment for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'EquipmentOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListEquipmentAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Results = foreach ($policy in $Rows) {
                    ($policy.Policy | ConvertFrom-Json)
                }
            }
        } elseif ($EquipmentId) {
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

    $Body = [PSCustomObject]@{
        Results  = @($Results | Where-Object { $_.Id -ne $null } | Sort-Object displayName)
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

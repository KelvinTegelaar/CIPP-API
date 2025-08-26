using namespace System.Net

function Invoke-ExecSetCalendarProcessing {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'ExecSetCalendarProcessing'
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $cmdParams = @{
            Identity                       = $Request.Body.UPN
            AutomateProcessing             = if ($Request.Body.automaticallyAccept -as [bool]) { 'AutoAccept' } elseif ($Request.Body.automaticallyProcess -as [bool]) { 'AutoUpdate' } else { 'None' }
            AllowConflicts                 = $Request.Body.allowConflicts -as [bool]
            AllowRecurringMeetings         = $Request.Body.allowRecurringMeetings -as [bool]
            ScheduleOnlyDuringWorkHours    = $Request.Body.scheduleOnlyDuringWorkHours -as [bool]
            AddOrganizerToSubject          = $Request.Body.addOrganizerToSubject -as [bool]
            DeleteComments                 = $Request.Body.deleteComments -as [bool]
            DeleteSubject                  = $Request.Body.deleteSubject -as [bool]
            RemovePrivateProperty          = $Request.Body.removePrivateProperty -as [bool]
            RemoveCanceledMeetings         = $Request.Body.removeCanceledMeetings -as [bool]
            RemoveOldMeetingMessages       = $Request.Body.removeOldMeetingMessages -as [bool]
            ProcessExternalMeetingMessages = $Request.Body.processExternalMeetingMessages -as [bool]
        }

        # Add optional numeric parameters only if they have values
        if ($Request.Body.maxConflicts) {
            $cmdParams['MaximumConflictInstances'] = $Request.Body.maxConflicts -as [int]
        }
        if ($Request.Body.maximumDurationInMinutes) {
            $cmdParams['MaximumDurationInMinutes'] = $Request.Body.maximumDurationInMinutes -as [int]
        }
        if ($Request.Body.minimumDurationInMinutes) {
            $cmdParams['MinimumDurationInMinutes'] = $Request.Body.minimumDurationInMinutes -as [int]
        }
        if ($Request.Body.bookingWindowInDays) {
            $cmdParams['BookingWindowInDays'] = $Request.Body.bookingWindowInDays -as [int]
        }
        if ($Request.Body.additionalResponse) {
            $cmdParams['AdditionalResponse'] = $Request.Body.additionalResponse
        }

        $null = New-ExoRequest -tenantid $Request.Body.tenantFilter -cmdlet 'Set-CalendarProcessing' -cmdParams $cmdParams
        
        $Results = "Calendar processing settings for $($Request.Body.UPN) have been updated successfully"
        Write-LogMessage -API $APIName -tenant $Request.Body.tenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not update calendar processing settings for $($Request.Body.UPN). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $Request.Body.tenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
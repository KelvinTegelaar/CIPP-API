function Remove-CIPPLicenseAfterOneDriveCopy {
    <#
    .SYNOPSIS
        Removes a leaver's licences only once their OneDrive copy has completed.
    .DESCRIPTION
        Used by the offboarding job in place of Remove-CIPPLicense when "Copy OneDrive to user(s)" is
        selected, because removing the licence starts the countdown to the OneDrive being deleted.

        Offboarding run (no OperationId): checks once the copy the same offboarding started, named by
        CopyOperationId (chosen by Invoke-CIPPOffboardingJob and given to the copy step). Any other copy
        of the same user, started by someone else or another run, is never taken for it.
          - Completed: hands over to Remove-CIPPLicense -Schedule, exactly as the normal step does.
          - Still queued or in progress: schedules itself as a recurring task (every 30 minutes) that
            checks again and removes the licences when the copy completes.
          - Failed, or no copy found (the copy step failed or was skipped): licences are NOT removed;
            the step fails with the reason. This is also what happens on a Craft host too old to run
            offboarding steps in order: if this step runs before the copy has started, it finds no copy
            and keeps the licences.

        Scheduled run (OperationId given): Completed removes the licences directly and ends the
        recurrence; Failed, an unknown operation, or passing Deadline ends the recurrence without
        removing them; otherwise it waits for the next check. Every outcome that leaves the licences in
        place is logged as an error, so it shows in the CIPP log and alerts.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # Object id of the leaver.
        [Parameter(Mandatory = $true)]
        [string]$userid,

        [string]$username,

        # Operation id the offboarding job gave its copy step.
        [string]$CopyOperationId,

        # Set by the follow-up scheduled task.
        [string]$OperationId,

        # Unix time after which the follow-up task stops waiting (0 = no deadline).
        [int64]$Deadline = 0,

        $APIName = 'Remove License',
        $Headers
    )

    $GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    if ($userid -notmatch $GuidPattern) { throw "Licences not removed: '$userid' is not a user object id." }
    $Name = if ($username) { $username } else { $userid }
    $Scheduled = -not [string]::IsNullOrWhiteSpace($OperationId)

    # Ends the recurring task this runs in (see Invoke-CIPPIntuneApprovalRetry). A no-op outside the scheduler.
    $StopChecking = {
        param([string]$Message, [string]$Sev)
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev $Sev
        $TaskId = $script:CippScheduledTaskIdStorage.Value
        if ($TaskId) {
            $Table = Get-CippTable -tablename 'ScheduledTasks'
            $null = Update-AzDataTableEntity -Force @Table -Entity @{ PartitionKey = 'ScheduledTask'; RowKey = [string]$TaskId; Recurrence = '0' }
        }
        $Message
    }
    $KeptMessage = { param($Reason) "Licences were NOT removed for $Name because $Reason Remove them manually once the OneDrive has been copied." }

    if (-not $Scheduled) { $OperationId = $CopyOperationId }

    # The operation must exist and be a copy of this user's OneDrive; otherwise a copy of someone else
    # (or a stale id) could release this user's licences.
    $Operation = $null
    if ($OperationId -match $GuidPattern) {
        $Table = Get-CIPPTable -TableName 'OneDriveCopyToUser'
        # Keyed by the tenant's customerId; copies started before that are under the raw tenantFilter.
        foreach ($ReadKey in (Get-CIPPOneDriveCopyTenantKey -TenantFilter $TenantFilter).ReadKeys) {
            $SafeKey = $ReadKey -replace "'", "''"
            $Operation = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeKey' and RowKey eq '$OperationId'") |
                Where-Object { $_.Kind -eq 'Operation' -and [string]$_.LeaverId -eq $userid } | Select-Object -First 1
            if ($Operation) { break }
        }
    }
    if (-not $Operation) {
        $Reason = if ($Scheduled) { "OneDrive copy $OperationId could not be found for this user." } else { 'the OneDrive copy step did not start a copy.' }
        $Message = & $KeptMessage $Reason
        if ($Scheduled) { return & $StopChecking $Message 'Error' }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error
        throw $Message
    }

    try {
        $Status = Update-CIPPOneDriveCopyToUserStatus -TenantFilter $TenantFilter -OperationId $OperationId
    } catch [System.Management.Automation.ItemNotFoundException] {
        $Message = & $KeptMessage "OneDrive copy $OperationId could not be found."
        if ($Scheduled) { return & $StopChecking $Message 'Error' }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error
        throw $Message
    }

    switch ($Status.State) {
        'Completed' {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -sev Info `
                -message "OneDrive copy $OperationId for $Name completed ($(@($Status.Recipients | ForEach-Object { "$($_.UserPrincipalName): $($_.ItemsCopied) files, $($_.BytesCopied) bytes" }) -join '; ')). Removing licences."
            if ($Scheduled) {
                $Result = Remove-CIPPLicense -userid $userid -username $username -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                return & $StopChecking "OneDrive copy $OperationId completed. $(@($Result) -join ' ')" 'Info'
            }
            return Remove-CIPPLicense -userid $userid -username $username -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -Schedule
        }
        'Failed' {
            $Details = @($Status.Recipients | Where-Object { $_.State -eq 'Failed' } | ForEach-Object { "$($_.UserPrincipalName): $($_.Message)" }) -join ' '
            $Message = & $KeptMessage "OneDrive copy $OperationId failed. $Details"
            if ($Scheduled) { return & $StopChecking $Message 'Error' }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error
            throw $Message
        }
    }

    # Still queued or in progress.
    $Now = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    if ($Scheduled) {
        if ($Deadline -gt 0 -and $Now -gt $Deadline) {
            return & $StopChecking (& $KeptMessage "OneDrive copy $OperationId had not completed by the deadline (state $($Status.State)).") 'Error'
        }
        return "OneDrive copy $OperationId is $($Status.State). Licences for $Name will be removed once it completes."
    }

    # The copy expires from storage after 14 days, so stop waiting just before that.
    $ScheduledTask = @{
        TenantFilter  = $TenantFilter
        Name          = "Remove License after OneDrive copy: $Name"
        Command       = @{ value = 'Remove-CIPPLicenseAfterOneDriveCopy' }
        Parameters    = [pscustomobject]@{
            userid      = $userid
            username    = $username
            OperationId = $OperationId
            Deadline    = $Now + 13 * 86400
            APIName     = 'Scheduled License Removal'
            Headers     = $Headers
        }
        ScheduledTime = $Now + 1800
        Recurrence    = '30m'
        PostExecution = @{ Webhook = $false; Email = $false; PSA = $false }
        Reference     = "OneDriveCopy-$OperationId"
    }
    # Add-CIPPScheduledTask reports most failures (a check for this user already pending, a storage
    # error) as an 'Error - ...' string rather than throwing; without the follow-up nothing would ever
    # remove the licences, so the step must fail rather than claim the removal is deferred.
    $TaskResult = @(Add-CIPPScheduledTask -Task $ScheduledTask -hidden $false -DisallowDuplicateName $true) -join ' '
    if ($TaskResult -like 'Error*') {
        $Message = & $KeptMessage "the follow-up check for OneDrive copy $OperationId could not be scheduled ($TaskResult)."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error
        throw $Message
    }
    $Message = "OneDrive copy $OperationId is $($Status.State). Licence removal for $Name is deferred: CIPP checks every 30 minutes and removes the licences once the copy completes, or leaves them in place if it fails."
    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Info
    return $Message
}

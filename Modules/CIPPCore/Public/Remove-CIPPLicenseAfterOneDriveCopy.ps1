function Remove-CIPPLicenseAfterOneDriveCopy {
    <#
    .SYNOPSIS
        Removes a leaver's licences only once their OneDrive copy has completed.
    .DESCRIPTION
        Offboarding run (CopyOperationId): Completed hands over to Remove-CIPPLicense -Schedule; still running
        schedules a 30-minute recurring check of itself; Failed or not found keeps the licences and throws.
        Scheduled run (OperationId): Completed removes the licences and ends the recurrence; Failed, not found or
        past Deadline ends it and keeps them.
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

    # Only a copy of this user's OneDrive may release their licences.
    $Operation = $null
    if ($OperationId -match $GuidPattern) {
        $Table = Get-CIPPTable -TableName 'OneDriveCopyToUser'
        $SafeKey = (Get-CIPPOneDriveCopyTenantKey -TenantFilter $TenantFilter) -replace "'", "''"
        $Operation = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeKey' and RowKey eq '$OperationId'").Where({ $_.Kind -eq 'Operation' -and [string]$_.LeaverId -eq $userid }, 'First')[0]
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
    # Add-CIPPScheduledTask reports most failures as an 'Error - ...' string rather than throwing.
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

function Invoke-ExecOnboardUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite,Identity.PrivilegedUser.ReadWrite
    .DESCRIPTION
        Runs the user onboarding wizard for a returning user: one scheduled onboarding job that applies
        the selected fixes, immediately or at the scheduled time, reporting live progress under one job
        id. Action=Rerun queues an existing onboarding task again; Action=RerunStep queues one step of
        it, reported to the same progress row.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Action = $Request.Query.Action ?? $Request.Body.Action
    if ($Action -in @('Rerun', 'RerunStep')) {
        try {
            # RowKey of the onboarding task to run again
            $TaskId = [string]$Request.Body.TaskId
            if (-not $TaskId) { $FailCode = [HttpStatusCode]::BadRequest; throw 'TaskId is required' }
            $TenantFilter = [string]($Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter)
            $Table = Get-CIPPTable -TableName 'ScheduledTasks'
            $SafeTaskId = $TaskId -replace "'", "''"
            $Task = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ScheduledTask' and RowKey eq '$SafeTaskId'"
            # Access to tenantFilter was checked on the way in; the task must belong to that tenant.
            if (-not $Task -or $Task.Command -ne 'Invoke-CIPPOnboardingJob' -or [string]$Task.Tenant -ne $TenantFilter) {
                $FailCode = [HttpStatusCode]::NotFound
                throw 'No onboarding task with that id exists in this tenant'
            }
            $Parameters = $Task.Parameters | ConvertFrom-Json
            $Targets = @(Get-CIPPPrivilegedUserTaskTarget -Command 'Invoke-CIPPOnboardingJob' -Parameters @{ Username = $Parameters.Username; Options = $Parameters.Options } -TenantFilter $TenantFilter)
            if ($Targets.Count -gt 0) { Assert-CippPrivilegedUserAccess -TenantFilter $TenantFilter -UserId $Targets }

            if ($Action -eq 'Rerun') {
                $Result = Add-CIPPScheduledTask -RunNow -RowKey $TaskId -Headers $Request.Headers
            } else {
                # Zero-based index of the step, as listed in the progress row, to run again
                $StepIndex = $Request.Body.StepIndex -as [int]
                if ($null -eq $Request.Body.StepIndex -or $null -eq $StepIndex) { $FailCode = [HttpStatusCode]::BadRequest; throw 'StepIndex is required' }
                # Title of that step, used to name the re-run task
                $StepTitle = [string]$Request.Body.StepTitle
                # A step re-run is its own scheduled task that reports to the original job's progress row.
                $taskObject = [PSCustomObject]@{
                    TenantFilter = $TenantFilter
                    Name         = "Onboarding: $($Parameters.Username) - re-run $(if ($StepTitle) { $StepTitle } else { "step $StepIndex" })"
                    Command      = @{ value = 'Invoke-CIPPOnboardingJob' }
                    Parameters   = [pscustomobject]@{
                        Username     = $Parameters.Username
                        Options      = $Parameters.Options
                        DeploymentId = $Parameters.DeploymentId
                        StepIndexes  = @($StepIndex)
                    }
                    Reference    = $Task.Reference
                }
                $Result = Add-CIPPScheduledTask -Task $taskObject -hidden $false -RunNow -Headers $Request.Headers
            }
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ Results = $Result }
                })
        } catch {
            return ([HttpResponseContext]@{
                    StatusCode = $FailCode ?? (Get-CippErrorStatusCode -ErrorRecord $_)
                    Body       = @{ Results = "Failed to queue the re-run: $($_.Exception.Message)" }
                })
        }
    }

    # Keep in sync with the step table in Invoke-CIPPOnboardingJob.
    $AllowedKeys = @(
        'EnableSignIn', 'AssignLicenses', 'ResetPassword', 'IssueTAP', 'SetManager', 'AddGroups', 'CopyGroupsFrom',
        'RemoveOneDriveSiteAdmins', 'ConvertToUserMailbox', 'UnhideFromGAL', 'RemoveForwarding', 'DisableOutOfOffice',
        'RemoveMailboxPermissions', 'RemoveCalendarPermissions', 'ProvisionOneDrive', 'SetMailboxLocale', 'EnableArchive',
        'GrantMailboxAccess', 'GrantCalendarAccess', 'AddOneDriveShortcuts'
    )
    $Errors = [System.Collections.Generic.List[string]]::new()

    $TenantFilter = [string]($Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter)
    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        $Errors.Add("'tenantFilter' is required.")
    }
    # The returning user: a user principal name or object id, as a string or an object with a 'value'
    $Username = $Request.Body.user.value ?? $Request.Body.user
    if ($Username -isnot [string] -or $Username -notmatch "^[^\s/\\?#%&']+$") {
        $Errors.Add("'user' is required and must be one user principal name or object id (a string, or an object with a 'value' property).")
    }
    # The fixes to run, each { Key, Params }
    $Fixes = @($Request.Body.Fixes | Where-Object { $null -ne $_ })
    if ($Fixes.Count -eq 0) {
        $Errors.Add("'Fixes' is required: select at least one fix to run.")
    }
    $UnknownKeys = @($Fixes | ForEach-Object { [string]$_.Key } | Where-Object { $_ -notin $AllowedKeys } | Sort-Object -Unique)
    if ($UnknownKeys.Count -gt 0) {
        $Errors.Add("Unknown fix key(s): $($UnknownKeys -join ', '). Allowed keys: $($AllowedKeys -join ', ').")
    }
    if ($Request.Body.Scheduled.enabled) {
        $Epoch = [int64]0
        if ($null -eq $Request.Body.Scheduled.date -or -not [int64]::TryParse([string]$Request.Body.Scheduled.date, [ref]$Epoch) -or $Epoch -le 0) {
            $Errors.Add("'Scheduled.enabled' is true but 'Scheduled.date' is not a valid Unix timestamp.")
        }
    }
    if ($Errors.Count -gt 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [pscustomobject]@{ Results = @($Errors) }
            })
    }

    try {
        # Only a job that enables sign-in, resets the password or issues a TAP is sensitive on a privileged user.
        $Targets = @(Get-CIPPPrivilegedUserTaskTarget -Command 'Invoke-CIPPOnboardingJob' -Parameters @{ Username = $Username; Options = @{ Fixes = $Fixes } } -TenantFilter $TenantFilter)
        if ($Targets.Count -gt 0) { Assert-CippPrivilegedUserAccess -TenantFilter $TenantFilter -UserId $Targets }
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = [pscustomobject]@{ Results = @($_.Exception.Message) }
            })
    }

    # Progress is a nice-to-have, so failing to create the row must not stop the onboarding itself.
    $DeploymentId = $null
    try {
        $DeploymentId = New-CIPPAsyncDeployment -Names @($Username) -Source 'Onboarding' -TenantFilter $TenantFilter
    } catch {
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Could not create the onboarding progress row: $($_.Exception.Message)" -sev Warning
    }

    try {
        $taskObject = [PSCustomObject]@{
            TenantFilter  = $TenantFilter
            Name          = "Onboarding: $Username"
            Command       = @{ value = 'Invoke-CIPPOnboardingJob' }
            Parameters    = [pscustomobject]@{
                Username     = $Username
                # Nested under Options: the scheduler mistakes a top-level list of objects with a Key for a dictionary.
                Options      = [pscustomobject]@{
                    Fixes = @($Fixes | ForEach-Object { [pscustomobject]@{ Key = [string]$_.Key; Params = $_.Params } })
                }
                DeploymentId = $DeploymentId
            }
            PostExecution = @{
                Webhook = [bool]$Request.Body.PostExecution.webhook
                Email   = [bool]$Request.Body.PostExecution.email
                PSA     = [bool]$Request.Body.PostExecution.psa
                Push    = [bool]$Request.Body.PostExecution.push
            }
            Reference     = $Request.Body.reference
            PsaTicketId   = $Request.Body.PsaTicketId
        }
        $Params = @{
            Task    = $taskObject
            hidden  = $false
            Headers = $Request.Headers
        }
        if ($Request.Body.Scheduled.enabled) {
            $taskObject | Add-Member -NotePropertyName ScheduledTime -NotePropertyValue $Request.Body.Scheduled.date
        } else {
            $Params.RunNow = $true
        }
        $Result = Add-CIPPScheduledTask @Params
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = [pscustomobject]@{ Results = @("Failed to queue the onboarding: $($_.Exception.Message)") }
            })
    }

    # The scheduler reports a refusal (blocked, privileged user, no push device) as a returned 'Error - ...' line.
    if ("$Result" -like 'Error*') {
        return ([HttpResponseContext]@{
                StatusCode = if ("$Result" -like 'Error - Could not add task*') { [HttpStatusCode]::InternalServerError } else { [HttpStatusCode]::BadRequest }
                Body       = [pscustomobject]@{ Results = @($Result) }
            })
    }

    $Body = [pscustomobject]@{ Results = @($Result) }
    if ($DeploymentId -and -not $Request.Body.Scheduled.enabled) {
        # Only a run-now job is worth polling straight away; a scheduled one is watched from its task page.
        $Body | Add-Member -NotePropertyName DeploymentId -NotePropertyValue $DeploymentId
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}

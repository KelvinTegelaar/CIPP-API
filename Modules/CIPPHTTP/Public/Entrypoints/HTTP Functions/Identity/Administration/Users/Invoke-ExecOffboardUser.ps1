function Invoke-ExecOffboardUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .DESCRIPTION
        Runs the offboarding wizard: one scheduled offboarding job per user, immediately or at the
        scheduled time, reporting live progress under one job id. Action=Rerun queues an existing
        offboarding task again; Action=RerunStep queues one step of it, reported to the same progress row.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Action = $Request.Query.Action ?? $Request.Body.Action
    if ($Action -in @('Rerun', 'RerunStep')) {
        try {
            # RowKey of the offboarding task to run again
            $TaskId = [string]$Request.Body.TaskId
            if (-not $TaskId) { throw 'TaskId is required' }
            $TenantFilter = [string]($Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter)
            $Table = Get-CIPPTable -TableName 'ScheduledTasks'
            $SafeTaskId = $TaskId -replace "'", "''"
            $Task = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ScheduledTask' and RowKey eq '$SafeTaskId'"
            # Access to tenantFilter was checked on the way in; the task must belong to that tenant.
            if (-not $Task -or $Task.Command -ne 'Invoke-CIPPOffboardingJob' -or [string]$Task.Tenant -ne $TenantFilter) {
                throw 'No offboarding task with that id exists in this tenant'
            }

            if ($Action -eq 'Rerun') {
                $Result = Add-CIPPScheduledTask -RunNow -RowKey $TaskId -Headers $Request.Headers
            } else {
                # Zero-based index of the step, as listed in the progress row, to run again
                $StepIndex = $Request.Body.StepIndex -as [int]
                if ($null -eq $StepIndex) { throw 'StepIndex is required' }
                # Title of that step, used to name the re-run task
                $StepTitle = [string]$Request.Body.StepTitle
                $Parameters = $Task.Parameters | ConvertFrom-Json
                # A step re-run is its own scheduled task (so it has results and logs of its own) that
                # reports to the original job's progress row.
                $taskObject = [PSCustomObject]@{
                    TenantFilter = $TenantFilter
                    Name         = "Offboarding: $($Parameters.Username) - re-run $(if ($StepTitle) { $StepTitle } else { "step $StepIndex" })"
                    Command      = @{ value = 'Invoke-CIPPOffboardingJob' }
                    Parameters   = [pscustomobject]@{
                        Username     = $Parameters.Username
                        APIName      = 'Scheduled Offboarding'
                        options      = $Parameters.options
                        RunScheduled = $true
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
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Failed to queue the re-run: $($_.Exception.Message)" }
                })
        }
    }

    $Validation = Test-CIPPOffboardingRequest -Body $Request.Body
    if (-not $Validation.IsValid) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [pscustomobject]@{ Results = @($Validation.Errors) }
            })
    }

    $AllUsers = $Validation.Users
    $TenantFilter = $Validation.TenantFilter
    $OffboardingOptions = $Request.Body | Select-Object * -ExcludeProperty user, tenantFilter, Scheduled

    # One live-progress job per wizard run with a queued row per user: the wizard polls it when
    # running now, and the task page shows it for any job. Progress is a nice-to-have, so failing to
    # create the rows must not stop the offboarding itself.
    $DeploymentId = $null
    try {
        $DeploymentId = New-CIPPAsyncDeployment -Names $AllUsers -Source 'Offboarding' -TenantFilter $TenantFilter
    } catch {
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Could not create the offboarding progress rows: $($_.Exception.Message)" -sev Warn
    }

    $StatusCode = [HttpStatusCode]::OK
    $Results = foreach ($username in $AllUsers) {
        try {
            $Headers = $Request.Headers
            $taskObject = [PSCustomObject]@{
                TenantFilter  = $TenantFilter
                Name          = "Offboarding: $Username"
                Command       = @{
                    value = 'Invoke-CIPPOffboardingJob'
                }
                Parameters    = [pscustomobject]@{
                    Username     = $Username
                    APIName      = 'Scheduled Offboarding'
                    options      = $OffboardingOptions
                    RunScheduled = $true
                    DeploymentId = $DeploymentId
                }
                PostExecution = @{
                    Webhook = [bool]$Request.Body.PostExecution.webhook
                    Email   = [bool]$Request.Body.PostExecution.email
                    PSA     = [bool]$Request.Body.PostExecution.psa
                }
                Reference     = $Request.Body.reference
                PsaTicketId   = $Request.Body.PsaTicketId
            }
            $Params = @{
                Task    = $taskObject
                hidden  = $false
                Headers = $Headers
            }
            if ($Request.Body.Scheduled.enabled) {
                $taskObject | Add-Member -NotePropertyName ScheduledTime -NotePropertyValue $Request.Body.Scheduled.date
            } else {
                $Params.RunNow = $true
            }
            Add-CIPPScheduledTask @Params
        } catch {
            $StatusCode = [HttpStatusCode]::Forbidden
            $_.Exception.message
        }
    }
    $body = [pscustomobject]@{'Results' = @($Results) }
    if ($DeploymentId -and -not $Request.Body.Scheduled.enabled) {
        # Only a run-now job is worth polling straight away; a scheduled one is watched from its task page.
        $body | Add-Member -NotePropertyName DeploymentId -NotePropertyValue $DeploymentId
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}

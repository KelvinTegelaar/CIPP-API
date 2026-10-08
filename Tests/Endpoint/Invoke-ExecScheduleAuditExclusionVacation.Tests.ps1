# Pester tests for Invoke-ExecScheduleAuditExclusionVacation.
#
# This is Vacation Mode's location alert half. It schedules two Set-CIPPAuditLogUserExclusion
# tasks: one adding the users to the audit log location exclusion list at the start date and one
# removing them at the end date. Unlike the Conditional Access half it needs no policy at all -
# the exclusion list is a CIPP table the audit log alert engine consults - which is exactly why
# the option exists standalone: tenants without CA policies still get location alerts.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Alerts/Invoke-ExecScheduleAuditExclusionVacation.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecScheduleAuditExclusionVacation.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, $DisallowDuplicateName) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath

    function New-VacationRequest {
        param([hashtable]$Body = @{})
        $RequestBody = [pscustomobject]@{
            tenantFilter  = 'contoso.com'
            startDate     = 1785000000
            endDate       = 1786000000
            reference     = 'Trip-42'
            postExecution = @('Email')
            Users         = @(
                [pscustomobject]@{
                    value       = 'user-guid'
                    addedFields = [pscustomobject]@{ userPrincipalName = 'sseck@contoso.com' }
                }
            )
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'ExecScheduleAuditExclusionVacation' }
        }
    }
}

Describe 'Invoke-ExecScheduleAuditExclusionVacation' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }

        # Snapshot each task at call time in case the endpoint ever mutates a shared object.
        $script:ScheduledTasks = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Add-CIPPScheduledTask -MockWith {
            $script:ScheduledTasks.Add(($Task | ConvertTo-Json -Depth 10 | ConvertFrom-Json))
        }
    }

    Context 'Scheduling the exclusion either side of the trip' {
        It 'adds the users to the location exclusion list at the start date' {
            $null = Invoke-ExecScheduleAuditExclusionVacation -Request (New-VacationRequest)

            $AddTask = $script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Add' }
            $AddTask | Should -Not -BeNullOrEmpty
            $AddTask.Command.value | Should -Be 'Set-CIPPAuditLogUserExclusion'
            $AddTask.Parameters.Users | Should -Be 'sseck@contoso.com'
            $AddTask.Parameters.Type | Should -Be 'Location'
            $AddTask.Parameters.TenantFilter | Should -Be 'contoso.com'
            $AddTask.ScheduledTime | Should -Be 1785000000
            $AddTask.TenantFilter | Should -Be 'contoso.com'
        }

        It 'removes the users from the location exclusion list at the end date' {
            $null = Invoke-ExecScheduleAuditExclusionVacation -Request (New-VacationRequest)

            $RemoveTask = $script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Remove' }
            $RemoveTask | Should -Not -BeNullOrEmpty
            $RemoveTask.Command.value | Should -Be 'Set-CIPPAuditLogUserExclusion'
            $RemoveTask.Parameters.Users | Should -Be 'sseck@contoso.com'
            $RemoveTask.ScheduledTime | Should -Be 1786000000
        }

        It 'schedules exactly one add and one remove as visible tasks' {
            # Visible because the vacation mode page lists them; a hidden remove could never be
            # cancelled and a missing one leaves the alerts suppressed permanently.
            $null = Invoke-ExecScheduleAuditExclusionVacation -Request (New-VacationRequest)

            Should -Invoke Add-CIPPScheduledTask -Times 2 -Exactly -ParameterFilter { $hidden -eq $false }
            @($script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Add' }).Count | Should -Be 1
            @($script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Remove' }).Count | Should -Be 1
        }

        It 'names both tasks so the vacation mode page finds them via *Vacation*' {
            $null = Invoke-ExecScheduleAuditExclusionVacation -Request (New-VacationRequest)

            ($script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Add' }).Name |
                Should -Be 'Add Location Alert Exclusion Vacation Mode: sseck@contoso.com'
            ($script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Remove' }).Name |
                Should -Be 'Remove Location Alert Exclusion Vacation Mode: sseck@contoso.com'
        }

        It 'carries the reference and post execution actions onto both tasks' {
            $null = Invoke-ExecScheduleAuditExclusionVacation -Request (New-VacationRequest)

            foreach ($Task in $script:ScheduledTasks) {
                $Task.Reference | Should -Be 'Trip-42'
                $Task.PostExecution | Should -Be @('Email')
            }
        }
    }

    Context 'Resolving who is excluded' {
        It 'excludes every selected user' {
            $Request = New-VacationRequest -Body @{
                Users = @(
                    [pscustomobject]@{ value = 'guid-1'; addedFields = [pscustomobject]@{ userPrincipalName = 'one@contoso.com' } }
                    [pscustomobject]@{ value = 'guid-2'; addedFields = [pscustomobject]@{ userPrincipalName = 'two@contoso.com' } }
                )
            }

            $null = Invoke-ExecScheduleAuditExclusionVacation -Request $Request

            ($script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Add' }).Parameters.Users |
                Should -Be @('one@contoso.com', 'two@contoso.com')
        }

        It 'falls back to the raw value when the option has no userPrincipalName' {
            $Request = New-VacationRequest -Body @{
                Users = @([pscustomobject]@{ value = 'fallback@contoso.com'; addedFields = [pscustomobject]@{} })
            }

            $null = Invoke-ExecScheduleAuditExclusionVacation -Request $Request

            ($script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Add' }).Parameters.Users |
                Should -Be 'fallback@contoso.com'
        }
    }

    Context 'Failures' {
        It 'schedules nothing without users' {
            $Response = Invoke-ExecScheduleAuditExclusionVacation -Request (New-VacationRequest -Body @{ Users = @() })

            $script:ScheduledTasks.Count | Should -Be 0
            $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
            "$($Response.Body.Results)" | Should -BeLike '*At least one user is required*'
        }

        It 'schedules nothing without both dates' {
            # Half a schedule would suppress the alerts and never restore them.
            $Response = Invoke-ExecScheduleAuditExclusionVacation -Request (New-VacationRequest -Body @{ endDate = $null })

            $script:ScheduledTasks.Count | Should -Be 0
            "$($Response.Body.Results)" | Should -BeLike '*start date and end date are required*'
        }
    }
}

# Pester tests for Invoke-ExecOffboardUser.
#
# The endpoint behind the Offboarding wizard. It does not offboard anything itself - it turns the
# request into one Invoke-CIPPOffboardingJob task per user, and that job is what calls
# Remove-CIPPGroups to pull the person out of their groups.
#
# The part worth pinning down is the options payload: it is built by stripping user, tenantFilter
# and Scheduled off the body, so every remaining switch - RemoveGroups included - has to survive
# into the task. An option dropped here silently does not happen, with no error anywhere.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecOffboardUser.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecOffboardUser.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Test-CIPPOffboardingRequest { param($Body) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, [switch]$RunNow, $DisallowDuplicateName, $RowKey) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-OffboardRequest {
        param([hashtable]$Body = @{}, [string[]]$Users = @('sseck@contoso.com'))
        $RequestBody = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            user         = $Users
            RemoveGroups = $true
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'ExecOffboardUser' }
            Query   = @{}
        }
    }

    function New-RerunRequest {
        param([string]$Action, [hashtable]$Body = @{})
        $RequestBody = [pscustomobject]@{ TaskId = 'task-1'; tenantFilter = 'contoso.com' }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'ExecOffboardUser' }
            Query   = @{ Action = $Action }
        }
    }

    function New-StoredOffboardingTask {
        param([string]$Command = 'Invoke-CIPPOffboardingJob', [string]$Tenant = 'contoso.com')
        [pscustomobject]@{
            RowKey     = 'task-1'
            Command    = $Command
            Tenant     = $Tenant
            Reference  = 'ticket-42'
            Parameters = (@{ Username = 'pat@contoso.com'; options = @{ RevokeSessions = $true; DisableSignIn = $true }; DeploymentId = 'job-1' } | ConvertTo-Json -Compress)
        }
    }
}

Describe 'Invoke-ExecOffboardUser' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPScheduledTask -MockWith { 'Successfully added task' }
        Mock -CommandName New-CIPPAsyncDeployment -MockWith { 'job-1' }
        Mock -CommandName Test-CIPPOffboardingRequest -MockWith {
            [pscustomobject]@{
                IsValid      = $true
                Users        = @($Body.user)
                TenantFilter = $Body.tenantFilter
                Errors       = @()
            }
        }
    }

    Context 'Turning the request into offboarding jobs' {
        It 'queues one offboarding job per user' {
            $Request = New-OffboardRequest -Users @('one@contoso.com', 'two@contoso.com', 'three@contoso.com')

            $null = Invoke-ExecOffboardUser -Request $Request

            Should -Invoke Add-CIPPScheduledTask -Times 3 -Exactly
            foreach ($User in 'one@contoso.com', 'two@contoso.com', 'three@contoso.com') {
                Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                    $Task.Parameters.Username -eq $User -and $Task.Command.value -eq 'Invoke-CIPPOffboardingJob'
                }
            }
        }

        It 'carries the group removal option into the job' {
            # Invoke-CIPPOffboardingJob reads this to decide whether to call Remove-CIPPGroups.
            $null = Invoke-ExecOffboardUser -Request (New-OffboardRequest)

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.options.RemoveGroups -eq $true
            }
        }

        It 'carries every other offboarding switch into the job' {
            $Request = New-OffboardRequest -Body @{
                RemoveLicenses     = $true
                ConvertToShared    = $true
                RevokeSessions     = $true
                RemoveMobile       = $false
                DisableSignIn      = $true
                RemovePermissions  = $true
            }

            $null = Invoke-ExecOffboardUser -Request $Request

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.options.RemoveLicenses -eq $true -and
                $Task.Parameters.options.ConvertToShared -eq $true -and
                $Task.Parameters.options.RevokeSessions -eq $true -and
                $Task.Parameters.options.RemoveMobile -eq $false -and
                $Task.Parameters.options.DisableSignIn -eq $true -and
                $Task.Parameters.options.RemovePermissions -eq $true
            }
        }

        It 'carries the Out of Office message into the job options' {
            $Ooo = '<p>No longer at %tenantname%.</p>'
            $Request = New-OffboardRequest -Body @{ OOO = $Ooo }

            $null = Invoke-ExecOffboardUser -Request $Request

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.options.OOO -eq $Ooo
            }
        }

        It 'strips the routing fields out of the options payload' {
            # user/tenantFilter/Scheduled are how the request was addressed, not things to do.
            $Request = New-OffboardRequest -Body @{ Scheduled = [pscustomobject]@{ enabled = $false } }

            $null = Invoke-ExecOffboardUser -Request $Request

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $null -eq $Task.Parameters.options.user -and
                $null -eq $Task.Parameters.options.tenantFilter -and
                $null -eq $Task.Parameters.options.Scheduled
            }
        }

        It 'targets the job at the validated tenant' {
            $null = Invoke-ExecOffboardUser -Request (New-OffboardRequest)

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.TenantFilter -eq 'contoso.com' -and $Task.Name -eq 'Offboarding: sseck@contoso.com'
            }
        }
    }

    Context 'Now versus later' {
        It 'runs the job immediately when no schedule was requested' {
            $null = Invoke-ExecOffboardUser -Request (New-OffboardRequest)

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $RunNow -eq $true }
        }

        It 'defers the job to the requested time instead of running it now' {
            $Request = New-OffboardRequest -Body @{ Scheduled = [pscustomobject]@{ enabled = $true; date = 1785000000 } }

            $null = Invoke-ExecOffboardUser -Request $Request

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.ScheduledTime -eq 1785000000 -and $RunNow -ne $true
            }
        }
    }

    Context 'Live progress' {
        It 'creates one queued progress row per user and hands the job id to every offboarding job' {
            $Request = New-OffboardRequest -Users @('one@contoso.com', 'two@contoso.com')

            $Response = Invoke-ExecOffboardUser -Request $Request

            Should -Invoke New-CIPPAsyncDeployment -Times 1 -Exactly -ParameterFilter {
                (@($Names) -join ',') -eq 'one@contoso.com,two@contoso.com' -and $Source -eq 'Offboarding'
            }
            Should -Invoke Add-CIPPScheduledTask -Times 2 -Exactly -ParameterFilter { $Task.Parameters.DeploymentId -eq 'job-1' }
            $Response.Body.DeploymentId | Should -Be 'job-1'
        }

        It 'does not hand back a job id for a deferred offboarding, which is watched from its task page' {
            $Request = New-OffboardRequest -Body @{ Scheduled = [pscustomobject]@{ enabled = $true; date = 1785000000 } }

            $Response = Invoke-ExecOffboardUser -Request $Request

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $Task.Parameters.DeploymentId -eq 'job-1' }
            $Response.Body.PSObject.Properties['DeploymentId'] | Should -BeNullOrEmpty
        }

        It 'still queues the offboarding when the progress rows cannot be created' {
            Mock -CommandName New-CIPPAsyncDeployment -MockWith { throw 'table unavailable' }

            $Response = Invoke-ExecOffboardUser -Request (New-OffboardRequest)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $null -eq $Task.Parameters.DeploymentId }
            $Response.Body.PSObject.Properties['DeploymentId'] | Should -BeNullOrEmpty
        }
    }

    Context 'Re-running' {
        BeforeEach {
            Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'ctx' } }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-StoredOffboardingTask }
        }

        It 'queues the whole task again through Run Now' {
            $Response = Invoke-ExecOffboardUser -Request (New-RerunRequest -Action 'Rerun')

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $RunNow -eq $true -and $RowKey -eq 'task-1' }
        }

        It 'queues a single step as its own task under the same progress job' {
            $Response = Invoke-ExecOffboardUser -Request (New-RerunRequest -Action 'RerunStep' -Body @{ StepIndex = 1; StepTitle = 'Disable sign in' })

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $RunNow -eq $true -and
                $Task.Command.value -eq 'Invoke-CIPPOffboardingJob' -and
                $Task.TenantFilter -eq 'contoso.com' -and
                $Task.Name -like '*Disable sign in*' -and
                $Task.Reference -eq 'ticket-42' -and
                $Task.Parameters.Username -eq 'pat@contoso.com' -and
                $Task.Parameters.DeploymentId -eq 'job-1' -and
                $Task.Parameters.options.DisableSignIn -eq $true -and
                (@($Task.Parameters.StepIndexes) -join ',') -eq '1'
            }
        }

        It 'accepts step zero' {
            $null = Invoke-ExecOffboardUser -Request (New-RerunRequest -Action 'RerunStep' -Body @{ StepIndex = 0 })

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { (@($Task.Parameters.StepIndexes) -join ',') -eq '0' }
        }

        It 'refuses a task that belongs to another tenant' {
            $Response = Invoke-ExecOffboardUser -Request (New-RerunRequest -Action 'Rerun' -Body @{ tenantFilter = 'other.com' })

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }

        It 'refuses a task that is not an offboarding job' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-StoredOffboardingTask -Command 'Invoke-Something' }

            $Response = Invoke-ExecOffboardUser -Request (New-RerunRequest -Action 'RerunStep' -Body @{ StepIndex = 1 })

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }
    }

    Context 'Guard rails' {
        It 'rejects an invalid request without queueing anything' {
            Mock -CommandName Test-CIPPOffboardingRequest -MockWith {
                [pscustomobject]@{ IsValid = $false; Errors = @('tenantFilter is required.'); Users = @(); TenantFilter = $null }
            }

            $Response = Invoke-ExecOffboardUser -Request (New-OffboardRequest)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -Contain 'tenantFilter is required.'
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }

        It 'keeps offboarding the remaining users when one fails to queue' {
            Mock -CommandName Add-CIPPScheduledTask -MockWith { throw 'scheduler unavailable' } -ParameterFilter { $Task.Parameters.Username -eq 'two@contoso.com' }
            $Request = New-OffboardRequest -Users @('one@contoso.com', 'two@contoso.com', 'three@contoso.com')

            $Response = Invoke-ExecOffboardUser -Request $Request

            Should -Invoke Add-CIPPScheduledTask -Times 3 -Exactly
            $Response.StatusCode | Should -Be ([HttpStatusCode]::Forbidden)
            $Response.Body.Results | Should -Contain 'scheduler unavailable'
        }
    }
}

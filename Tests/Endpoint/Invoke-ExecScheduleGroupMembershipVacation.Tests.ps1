# Pester tests for Invoke-ExecScheduleGroupMembershipVacation.
#
# Each selected group gets one add task at the start date and one remove task at the end date,
# both carrying the same MembershipKey so the remove only takes out the users the add put in.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecScheduleGroupMembershipVacation.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecScheduleGroupMembershipVacation.ps1 at $FunctionPath" }

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
                [pscustomobject]@{ value = 'guid-1'; addedFields = [pscustomobject]@{ userPrincipalName = 'one@contoso.com' } }
                [pscustomobject]@{ value = 'guid-2'; addedFields = [pscustomobject]@{ userPrincipalName = 'two@contoso.com' } }
            )
            Groups        = @(
                [pscustomobject]@{ value = 'group-1'; label = 'Travel Exclusions'; addedFields = [pscustomobject]@{} }
            )
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'ExecScheduleGroupMembershipVacation' }
        }
    }
}

Describe 'Invoke-ExecScheduleGroupMembershipVacation' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        $script:ScheduledTasks = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Add-CIPPScheduledTask -MockWith {
            $script:ScheduledTasks.Add(($Task | ConvertTo-Json -Depth 10 | ConvertFrom-Json))
        }
    }

    It 'schedules one add and one remove per group sharing a membership key' {
        $Response = Invoke-ExecScheduleGroupMembershipVacation -Request (New-VacationRequest)

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        Should -Invoke Add-CIPPScheduledTask -Times 2 -Exactly -ParameterFilter { $hidden -eq $false }

        $AddTask = $script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Add' }
        $RemoveTask = $script:ScheduledTasks | Where-Object { $_.Parameters.Action -eq 'Remove' }
        @($AddTask).Count | Should -Be 1
        @($RemoveTask).Count | Should -Be 1

        $AddTask.Command.value | Should -Be 'Set-CIPPVacationGroupMembership'
        $RemoveTask.Command.value | Should -Be 'Set-CIPPVacationGroupMembership'
        $AddTask.ScheduledTime | Should -Be 1785000000
        $RemoveTask.ScheduledTime | Should -Be 1786000000
        $AddTask.Parameters.MembershipKey | Should -Not -BeNullOrEmpty
        $RemoveTask.Parameters.MembershipKey | Should -Be $AddTask.Parameters.MembershipKey
        $AddTask.Parameters.GroupId | Should -Be 'group-1'
        $AddTask.Parameters.Users | Should -Be @('one@contoso.com', 'two@contoso.com')
        $AddTask.Name | Should -Be 'Add Group Membership Vacation Mode: Travel Exclusions - one@contoso.com, two@contoso.com'
        $RemoveTask.Name | Should -Be 'Remove Group Membership Vacation Mode: Travel Exclusions - one@contoso.com, two@contoso.com'
        $AddTask.Reference | Should -Be 'Trip-42'
    }

    It 'gives each group its own membership key' {
        $Request = New-VacationRequest -Body @{
            Groups = @(
                [pscustomobject]@{ value = 'group-1'; label = 'One' }
                [pscustomobject]@{ value = 'group-2'; label = 'Two' }
            )
        }

        $null = Invoke-ExecScheduleGroupMembershipVacation -Request $Request

        $script:ScheduledTasks.Count | Should -Be 4
        @($script:ScheduledTasks.Parameters.MembershipKey | Select-Object -Unique).Count | Should -Be 2
    }

    It 'schedules nothing without users' {
        $Response = Invoke-ExecScheduleGroupMembershipVacation -Request (New-VacationRequest -Body @{ Users = @() })

        $script:ScheduledTasks.Count | Should -Be 0
        "$($Response.Body.Results)" | Should -BeLike '*At least one user is required*'
    }

    It 'schedules nothing without groups' {
        $Response = Invoke-ExecScheduleGroupMembershipVacation -Request (New-VacationRequest -Body @{ Groups = @() })

        $script:ScheduledTasks.Count | Should -Be 0
        $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
        "$($Response.Body.Results)" | Should -BeLike '*At least one group is required*'
    }
}

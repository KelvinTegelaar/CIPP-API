BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File | Select-Object -First 1 -ExpandProperty FullName
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Get-CIPPPrivilegedUserTaskTarget.ps1')

    function Assert-CippPrivilegedUserAccess { param($TenantFilter, $UserId, [switch]$Enforce) }
    function Set-CippScheduledTaskContext { param($TaskId, $AlertReNotify, $AlertRun, $PrivilegedUserRestricted) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter, $Property) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Get-CIPPScheduledTaskNextRun { param($Recurrence, $ScheduledTime) 5000 }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Send-CIPPScheduledTaskAlert { param($Results, $TaskInfo, $TenantFilter, $TaskType, $Attachments) }
    function Get-DeltaQueryUrl { param($TenantFilter, $PartitionKey) }
    function New-GraphDeltaQuery { param($DeltaUrl, $TenantFilter, $PartitionKey) }
    function Test-DeltaQueryConditions { param($Query, $Trigger, $TenantFilter, $LastTrigger) }
    $null = New-Module -Name CIPPCore -ScriptBlock { function Clear-CIPPImmutableID { param($UserID, $TenantFilter) } } | Import-Module -Force -PassThru

    . $FunctionPath

    function New-TaskItem([bool]$Restricted, [bool]$PerResource) {
        $TaskInfo = [pscustomobject]@{
            PartitionKey  = 'ScheduledTask'
            RowKey        = 'task-1'
            Name          = 'Clear immutable ID'
            Command       = 'Clear-CIPPImmutableID'
            Tenant        = 'a.onmicrosoft.com'
            Recurrence    = '0'
            ScheduledTime = '1000'
            TaskState     = 'Pending'
            PostExecution = ''
        }
        if ($Restricted) { $TaskInfo | Add-Member -NotePropertyName PrivilegedUserRestricted -NotePropertyValue $true }
        if ($PerResource) { $TaskInfo | Add-Member -NotePropertyName Trigger -NotePropertyValue (@{ Type = 'DeltaQuery'; ExecutePerResource = $true } | ConvertTo-Json -Compress) }
        [pscustomobject]@{
            Command    = 'Clear-CIPPImmutableID'
            Parameters = @{ TenantFilter = 'a.onmicrosoft.com'; UserID = $(if ($PerResource) { '%id%' } else { 'admin@a.onmicrosoft.com' }) }
            TaskInfo   = $TaskInfo
        }
    }
}

AfterAll {
    Remove-Module -Name CIPPCore -Force -ErrorAction SilentlyContinue
}

Describe 'Push-ExecScheduledCommand for privileged users' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Set-CippScheduledTaskContext {}
        Mock Set-CippUserAgentContext {}
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Get-AzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Pending' } }
        Mock Update-AzDataTableEntity { $script:Writes.Add($Entity) }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-a' } }
        Mock Get-CippException { @{ NormalizedError = $Exception.Exception.Message } }
        Mock Write-LogMessage {}
        Mock Send-CIPPScheduledTaskAlert {}
        Mock Get-DeltaQueryUrl { 'https://graph.example/delta' }
        Mock New-GraphDeltaQuery { @{ value = @() } }
        Mock Test-DeltaQueryConditions { @{ ConditionsMet = $true; MatchedData = @(@{ id = 'admin-id' }, @{ id = 'user-id' }) } }
        Mock Clear-CIPPImmutableID { 'Cleared' }
        Mock Assert-CippPrivilegedUserAccess { if ($UserId -contains 'admin-id' -or $UserId -contains 'admin@a.onmicrosoft.com') { throw "$UserId holds a privileged admin role." } }
    }

    It 'fails a restricted task whose target is privileged without running the command' {
        $null = Push-ExecScheduledCommand -Item (New-TaskItem -Restricted $true)

        Should -Invoke Clear-CIPPImmutableID -Times 0 -Exactly
        $script:Writes[-1].TaskState | Should -Be 'Failed'
        $script:Writes[-1].Results | Should -BeLike '*holds a privileged admin role*'
    }

    It 'checks each user a delta trigger resolves and runs only the allowed ones' {
        $null = Push-ExecScheduledCommand -Item (New-TaskItem -Restricted $true -PerResource $true)

        Should -Invoke Assert-CippPrivilegedUserAccess -Times 2 -Exactly -ParameterFilter { $Enforce }
        Should -Invoke Clear-CIPPImmutableID -Times 1 -Exactly -ParameterFilter { $UserID -eq 'user-id' }
    }

    It 'runs an unrestricted task without checking' {
        $null = Push-ExecScheduledCommand -Item (New-TaskItem -Restricted $false)

        Should -Invoke Assert-CippPrivilegedUserAccess -Times 0 -Exactly
        Should -Invoke Clear-CIPPImmutableID -Times 1 -Exactly
    }
}

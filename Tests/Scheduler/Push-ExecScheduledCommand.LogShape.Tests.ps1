# Pins what Push-ExecScheduledCommand writes to the Craft log for each task shape.
#
# A report builder task carries the whole report definition in its parameters, so logging the task or its
# parameters as JSON wrote ~635 KB per tenant per line. The task is logged as a one-line summary and the
# parameters as capped JSON without the stored request headers or the injected TaskInfo.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-ExecScheduledCommand.ps1 under Modules/' }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPScheduledTaskNextRun.ps1')

    function Set-CippScheduledTaskContext { param($TaskId, $AlertReNotify) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Send-CIPPScheduledTaskAlert { param($Results, $TaskInfo, $TenantFilter, $TaskType, $Attachments) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    # Each command declares Headers, so the unknown-parameter strip does not remove it before logging.
    function Push-ExecGenerateReportBuilderReport { param($TenantFilter, $TemplateName, $Blocks, $Headers) 'Successfully generated report' }
    function Invoke-CIPPOffboardingJob { param($TenantFilter, $Username, $Options, $Headers, $TaskInfo) 'Offboarding queued' }
    function Add-CIPPGroupMember { param($TenantFilter, $GroupType, $Member, $GroupId, $Headers) 'Added member' }

    $script:PrincipalMarker = 'eyJpZGVudGl0eVByb3ZpZGVyIjoiYWFkIn0-principal-marker'

    function New-ShapeItem {
        param([string]$Command, [string]$Name, [string]$Tenant, [hashtable]$Parameters)
        $Parameters.Headers = @{ 'x-ms-client-principal' = $script:PrincipalMarker }
        $TaskInfo = [pscustomobject]@{
            PartitionKey = 'ScheduledTask'
            RowKey       = 'task-shape-1'
            Name         = $Name
            Command      = $Command
            Tenant       = $Tenant
            Recurrence   = '0'
            TaskState    = 'Planned'
            Parameters   = $Parameters
        }
        [pscustomobject]@{ Command = $Command; Parameters = $Parameters; TaskInfo = $TaskInfo }
    }

    function Get-TaskLogLines {
        param($Item)
        @(Push-ExecScheduledCommand -Item $Item 6>&1 | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData })
    }

    . $FunctionPath
}

Describe 'Push-ExecScheduledCommand log shape' {
    BeforeEach {
        Mock Set-CippScheduledTaskContext {}
        Mock Set-CippUserAgentContext {}
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Update-AzDataTableEntity {}
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-1' } }
        Mock Write-LogMessage {}
        Mock Send-CIPPScheduledTaskAlert {}
        Mock Get-AzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-shape-1'; TaskState = 'Pending' } }
        # The SUT reads the module gate and parameter names from Get-Command, then invokes the command by name.
        Mock Get-Command {
            $Params = @{}
            foreach ($P in 'TenantFilter', 'TemplateName', 'Blocks', 'Username', 'Options', 'TaskInfo', 'GroupType', 'Member', 'GroupId', 'Headers') { $Params[$P] = [pscustomobject]@{ Name = $P } }
            [pscustomobject]@{ Module = 'CIPPCore'; Parameters = $Params }
        }

        $script:Shapes = @(
            New-ShapeItem -Command 'Push-ExecGenerateReportBuilderReport' -Name 'Scheduled tenUsers365 - AllTenants' -Tenant 'contoso.onmicrosoft.com' -Parameters @{
                TemplateName = 'tenUsers365'
                Blocks       = '[{"type":"database","title":"Users","content":"' + ('x' * 700000) + '"}]'
                TenantFilter = 'contoso.onmicrosoft.com'
            }
            New-ShapeItem -Command 'Invoke-CIPPOffboardingJob' -Name 'Offboarding: user@contoso.com' -Tenant 'contoso.onmicrosoft.com' -Parameters @{
                Username     = 'user@contoso.com'
                Options      = @{ RevokeSessions = $true; DisableSignIn = $true }
                TenantFilter = 'contoso.onmicrosoft.com'
            }
            New-ShapeItem -Command 'Add-CIPPGroupMember' -Name 'Add CA Exclusion Vacation Mode' -Tenant 'contoso.onmicrosoft.com' -Parameters @{
                GroupType    = 'Security'
                Member       = 'user@contoso.com'
                GroupId      = 'f71bf6c1-c60c-4bce-a2db-994ba788657e'
                TenantFilter = 'contoso.onmicrosoft.com'
            }
        )
    }

    It 'logs the task as a one-line summary for <Command>' -ForEach @(
        @{ Index = 0; Command = 'Push-ExecGenerateReportBuilderReport' }
        @{ Index = 1; Command = 'Invoke-CIPPOffboardingJob' }
        @{ Index = 2; Command = 'Add-CIPPGroupMember' }
    ) {
        $Item = $script:Shapes[$Index]
        $Summary = @(Get-TaskLogLines $Item | Where-Object { $_ -like 'We are going to be running a scheduled task:*' })
        $Summary.Count | Should -Be 1
        $Summary[0] | Should -Be "We are going to be running a scheduled task: $($Item.TaskInfo.Name) (task-shape-1), command $Command, tenant contoso.onmicrosoft.com, recurrence 0, state Planned"
    }

    It 'logs the parameters as compact JSON without Headers or TaskInfo for <Command>' -ForEach @(
        @{ Index = 1; Command = 'Invoke-CIPPOffboardingJob'; Keys = 'Options,TenantFilter,Username' }
        @{ Index = 2; Command = 'Add-CIPPGroupMember'; Keys = 'GroupId,GroupType,Member,TenantFilter' }
    ) {
        $Start = @(Get-TaskLogLines $script:Shapes[$Index] | Where-Object { $_ -like "Starting task: $Command for tenant: contoso.onmicrosoft.com with parameters: *" })
        $Start.Count | Should -Be 1
        $Logged = $Start[0].Substring($Start[0].IndexOf('with parameters: ') + 17) | ConvertFrom-Json -AsHashtable
        ($Logged.Keys | Sort-Object) -join ',' | Should -Be $Keys
    }

    It 'caps the parameters line of a report builder task' {
        $Start = @(Get-TaskLogLines $script:Shapes[0] | Where-Object { $_ -like 'Starting task: Push-ExecGenerateReportBuilderReport*' })
        $Start.Count | Should -Be 1
        $Start[0].Length | Should -BeLessThan 4500
        # Hashtable key order varies per process, so only the envelope is pinned, not which key survives the cut.
        $Start[0] | Should -BeLike 'Starting task: Push-ExecGenerateReportBuilderReport for tenant: contoso.onmicrosoft.com with parameters: {"*...`[truncated`]'
    }

    It 'keeps every log line small and free of the stored principal for <Command>' -ForEach @(
        @{ Index = 0; Command = 'Push-ExecGenerateReportBuilderReport' }
        @{ Index = 1; Command = 'Invoke-CIPPOffboardingJob' }
        @{ Index = 2; Command = 'Add-CIPPGroupMember' }
    ) {
        $Lines = Get-TaskLogLines $script:Shapes[$Index]
        $Lines.Count | Should -BeGreaterThan 0
        @($Lines | Where-Object { $_.Length -gt 4500 }) | Should -BeNullOrEmpty
        @($Lines | Where-Object { $_ -like "*$script:PrincipalMarker*" }) | Should -BeNullOrEmpty
    }
}

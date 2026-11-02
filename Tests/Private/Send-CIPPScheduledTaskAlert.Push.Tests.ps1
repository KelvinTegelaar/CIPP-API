# Pester tests for the push channel in Send-CIPPScheduledTaskAlert.
#
# Pins who a push notification goes to: the CIPP operator whose principal was stored on the
# task when it was created, resolved from the decoded x-ms-client-principal so it matches the
# key the subscribe endpoint uses. Never the M365 user the task acted on, and never the
# -name header alone, which is the app id for API clients.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Send-CIPPScheduledTaskAlert.ps1'
    Add-Type -AssemblyName System.Web

    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPTable { param($TableName) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-AlertContentHash { param($AlertItem) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Send-CIPPAlert { param($Type, $TargetUser, $Title, $PushMessage, $Url, $APIName, $HTMLContent, $JSONContent, $TenantFilter, $SchemaSource, $InvokingCommand, [switch]$UseStandardizedSchema, $Attachments) }

    . $FunctionPath

    function New-TaskInfo {
        param([string]$Operator = 'tech@msp.example', [string]$PrincipalName = $Operator, [string]$PostExecution = 'Push')
        $Principal = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((@{ userDetails = $Operator } | ConvertTo-Json -Compress)))
        [pscustomobject]@{
            PartitionKey  = 'ScheduledTask'
            RowKey        = 'task-1'
            Name          = 'Offboarding: pat@contoso.com'
            Command       = 'Invoke-CIPPOffboardingJob'
            PostExecution = $PostExecution
            Parameters    = (@{
                    Username = 'pat@contoso.com'
                    Headers  = @{ 'x-ms-client-principal' = $Principal; 'x-ms-client-principal-name' = $PrincipalName }
                } | ConvertTo-Json -Compress -Depth 5)
        }
    }
}

Describe 'Send-CIPPScheduledTaskAlert push channel' {
    BeforeEach {
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.com' } }
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Get-CippTable { @{ Context = 'ctx' } }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Write-LogMessage { }
        Mock Send-CIPPAlert { 'Push sent to 1 of 1 device(s)' }
    }

    It 'targets the operator from the decoded principal, not the user the task acted on' {
        $Outcomes = Send-CIPPScheduledTaskAlert -Results 'Offboarding completed successfully for pat@contoso.com' -TaskInfo (New-TaskInfo) -TenantFilter 'contoso.com' -TaskType 'User Offboarding'
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'push' -and $TargetUser -eq 'tech@msp.example' -and $Url -eq '/cipp/scheduler/task?id=task-1' }
        Should -Invoke Send-CIPPAlert -Times 0 -ParameterFilter { $TargetUser -eq 'pat@contoso.com' }
        @($Outcomes | Where-Object Channel -EQ 'Push').Count | Should -Be 1
    }

    It 'prefers the decoded principal over the -name header' {
        # An API client carries its app id in -name; the stored principal still names the user.
        Send-CIPPScheduledTaskAlert -Results 'done' -TaskInfo (New-TaskInfo -PrincipalName '00000000-0000-0000-0000-000000000000') -TenantFilter 'contoso.com' | Out-Null
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'push' -and $TargetUser -eq 'tech@msp.example' }
    }

    It 'sends nothing by push when Push is not among the post-execution channels' {
        Send-CIPPScheduledTaskAlert -Results 'done' -TaskInfo (New-TaskInfo -PostExecution 'Email') -TenantFilter 'contoso.com' | Out-Null
        Should -Invoke Send-CIPPAlert -Times 0 -ParameterFilter { $Type -eq 'push' }
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'email' }
    }
}

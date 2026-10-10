# Callers that pass the task or its Parameters as a hashtable must be stored the same as a
# [pscustomobject]: a future ScheduledTime kept as a Unix-time string, and the real parameter keys.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPScheduledTask.ps1'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CippQueueMessage { param($Cmdlet, $Parameters) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $tenantid, $LogData) }

    . $FunctionPath

    $script:Future = [string][int64]([DateTimeOffset]::UtcNow.AddDays(30).ToUnixTimeSeconds())
}

Describe 'Add-CIPPScheduledTask hashtable input' {
    BeforeEach {
        $script:CapturedEntity = $null
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:CapturedEntity = $Entity }
        Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Module = 'CIPPCore'; Parameters = @{} } }
    }

    It 'keeps a future ScheduledTime from a hashtable task' {
        Add-CIPPScheduledTask -Task @{
            Name          = 'Hashtable task'
            Command       = @{ value = 'Write-LogMessage' }
            TenantFilter  = 'contoso.onmicrosoft.com'
            Parameters    = [pscustomobject]@{ message = 'hi' }
            ScheduledTime = $script:Future
        }

        $script:CapturedEntity.ScheduledTime | Should -BeOfType [string]
        $script:CapturedEntity.ScheduledTime | Should -Be $script:Future
    }

    It 'stores the keys of hashtable Parameters' {
        Add-CIPPScheduledTask -Task ([pscustomobject]@{
                Name          = 'Hashtable parameters'
                Command       = @{ value = 'Write-LogMessage' }
                TenantFilter  = 'contoso.onmicrosoft.com'
                Parameters    = @{ message = 'hi'; Sev = 'Info' }
                ScheduledTime = $script:Future
            })

        $Stored = $script:CapturedEntity.Parameters | ConvertFrom-Json -AsHashtable
        $Stored.Keys | Sort-Object | Should -Be @('message', 'Sev')
        $Stored.message | Should -Be 'hi'
    }

    It 'stores ScheduledTime as a string when re-queuing with RunNow' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'abc'; Name = 'Existing'; ScheduledTime = $script:Future; TaskState = 'Completed' }
        }
        Mock -CommandName Add-CippQueueMessage -MockWith { $true }

        Add-CIPPScheduledTask -RunNow -RowKey 'abc'

        $script:CapturedEntity.ScheduledTime | Should -BeOfType [string]
        [int64]$script:CapturedEntity.ScheduledTime | Should -BeLessThan ([int64]$script:Future)
    }
}

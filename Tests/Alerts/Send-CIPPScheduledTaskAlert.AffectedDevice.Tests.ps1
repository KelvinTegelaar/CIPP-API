# Pester tests for the device a scheduled task's PSA alert carries: device-targeted tasks name the
# managed device in their parameters, and the link also works when only NinjaOne ticketing is on.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPTextReplacement { param($Text, $TenantFilter, [switch]$EscapeForJson) }
    function Send-CIPPAlert {
        param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $altEmail, $altWebhook,
            $APIName, $SchemaSource, $InvokingCommand, $Headers, $TableName, $RowKey,
            $Attachments, $AffectedUser, $AffectedDevice, $PSAReference, $PSATicketId, $PSAConsolidationKey, $PsaTicketPriority, [switch]$UseStandardizedSchema)
    }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-PSAHtml.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AlertContentHash.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Send-CIPPScheduledTaskAlert.ps1')

    function New-ExtConfig {
        param([bool]$Halo = $true, [bool]$NinjaTicketing = $false, [bool]$NinjaLink = $false)
        [pscustomobject]@{
            config = (@{
                    HaloPSA  = @{ Enabled = $Halo; LinkTicketsToUsers = $false }
                    NinjaOne = @{ Enabled = $true; TicketingEnabled = $NinjaTicketing; LinkTicketsToUsers = $NinjaLink }
                } | ConvertTo-Json -Depth 5)
        }
    }
}

Describe 'Send-CIPPScheduledTaskAlert - affected device' {
    BeforeEach {
        $script:Sent = [System.Collections.Generic.List[object]]::new()
        $script:ExtConfig = New-ExtConfig
        $script:Results = @([pscustomobject]@{ Result = 'Sync requested' })
        $script:TaskInfo = [pscustomobject]@{
            RowKey        = 'task-dev'
            Name          = 'Sync device'
            Command       = 'Invoke-ExecDeviceAction'
            PostExecution = 'psa'
            Parameters    = (@{ GUID = 'cccccccc-3333-4333-8333-333333333333'; Action = 'syncDevice'; DeviceName = 'LAPTOP-01' } | ConvertTo-Json -Compress)
        }
        Mock -CommandName Get-CippTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = '00000000-0000-0000-0000-000000000001' } }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { param($Text, $TenantFilter) $Text }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            switch ($TableName) {
                'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                'Extensionsconfig' { $script:ExtConfig }
                default { $null }
            }
        }
        Mock -CommandName Send-CIPPAlert -MockWith {
            param($Type, $Title, $AffectedUser, $AffectedDevice)
            $script:Sent.Add([pscustomobject]@{ Type = $Type; Title = $Title; AffectedUser = $AffectedUser; AffectedDevice = $AffectedDevice })
        }
    }

    It 'carries the managed device from a device action task' {
        Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'
        $script:Sent.Count | Should -Be 1
        $script:Sent[0].AffectedDevice.IntuneId | Should -Be 'cccccccc-3333-4333-8333-333333333333'
        $script:Sent[0].AffectedDevice.DisplayName | Should -Be 'LAPTOP-01'
        $script:Sent[0].AffectedUser | Should -BeNullOrEmpty
    }

    It 'carries a serial number when the task names one' {
        $script:TaskInfo.Parameters = (@{ SerialNumber = 'SER123'; input = '%SERIAL%' } | ConvertTo-Json -Compress)
        Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'
        $script:Sent[0].AffectedDevice.SerialNumber | Should -Be 'SER123'
        $script:Sent[0].AffectedDevice.IntuneId | Should -BeNullOrEmpty
    }

    It 'sends no device when the task names none' {
        $script:TaskInfo.Parameters = (@{ UserPrincipalName = 'user1@contoso.com' } | ConvertTo-Json -Compress)
        Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'
        $script:Sent[0].AffectedDevice | Should -BeNullOrEmpty
        $script:Sent[0].AffectedUser.UPN | Should -Be 'user1@contoso.com'
    }

    It 'resolves the device and user when only NinjaOne ticketing is enabled' {
        $script:ExtConfig = New-ExtConfig -Halo $false -NinjaTicketing $true
        Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'
        $script:Sent[0].AffectedDevice.IntuneId | Should -Be 'cccccccc-3333-4333-8333-333333333333'
    }

    It 'resolves nothing when no ticketing integration is enabled' {
        $script:ExtConfig = New-ExtConfig -Halo $false -NinjaTicketing $false
        Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'
        $script:Sent[0].AffectedDevice | Should -BeNullOrEmpty
    }
}

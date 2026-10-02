# Pester tests for the Push enrolment guard in Add-CIPPScheduledTask.
# A task that asks for Push from a user with no registered devices would notify nobody, so the
# creation is refused with a pointer to Preferences. Other channels and enrolled users pass.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Add-CIPPScheduledTask.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $First) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CippQueueMessage { param($Cmdlet, $Parameters) }
    function Get-CIPPSchedulerBlockedCommands { }
    function Get-NormalizedError { param($Message) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $Tenant) }

    . $FunctionPath

    $script:Headers = @{ 'x-ms-client-principal' = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((@{ userDetails = 'tech@msp.example' } | ConvertTo-Json -Compress))) }
    function New-TaskRequest {
        param([string[]]$Channels = @('Push'))
        [pscustomobject]@{
            TenantFilter  = 'contoso.com'
            Name          = 'Nightly report'
            Command       = @{ value = 'Get-CIPPLicenseOverview' }
            Parameters    = [pscustomobject]@{ TenantFilter = 'contoso.com' }
            ScheduledTime = 0
            PostExecution = @{ value = $Channels }
        }
    }
}

Describe 'Add-CIPPScheduledTask Push enrolment guard' {
    BeforeEach {
        $script:Persisted = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPTable { @{ Context = $TableName } }
        Mock Add-CIPPAzDataTableEntity { $script:Persisted.Add($Entity) }
        Mock Add-CippQueueMessage { }
        Mock Get-CIPPSchedulerBlockedCommands { @() }
        Mock Get-NormalizedError { $Message }
        Mock Write-LogMessage { }
        Mock Get-Command -ParameterFilter { $Name -eq 'Get-CIPPLicenseOverview' } -MockWith {
            [pscustomobject]@{ Name = 'Get-CIPPLicenseOverview'; Module = 'CIPPCore'; Parameters = @{ TenantFilter = 1 } }
        }
    }

    It 'refuses Push for a user with no registered devices and persists nothing' {
        Mock Get-CIPPAzDataTableEntity { @() }
        $Result = Add-CIPPScheduledTask -Task (New-TaskRequest) -Hidden $false -Headers $script:Headers
        $Result | Should -Match 'no push notification devices'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -eq "PartitionKey eq 'tech@msp.example'" }
        $script:Persisted.Count | Should -Be 0
    }

    It 'accepts Push once a device is registered' {
        Mock Get-CIPPAzDataTableEntity { if ($Filter -like "PartitionKey eq 'tech@msp.example'*") { [pscustomobject]@{ RowKey = 'dev-1' } } else { @() } }
        $Result = Add-CIPPScheduledTask -Task (New-TaskRequest) -Hidden $false -Headers $script:Headers
        $Result | Should -Not -Match '^Error'
        @($script:Persisted | Where-Object { $_.PostExecution -eq 'Push' }).Count | Should -BeGreaterThan 0
    }

    It 'does not consult the device table when Push is not selected' {
        Mock Get-CIPPAzDataTableEntity { @() }
        Add-CIPPScheduledTask -Task (New-TaskRequest -Channels @('Email')) -Hidden $false -Headers $script:Headers | Should -Not -Match '^Error'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -ParameterFilter { $Filter -like "PartitionKey eq 'tech@msp.example'*" }
    }
}

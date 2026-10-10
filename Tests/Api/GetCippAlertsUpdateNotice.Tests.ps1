BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPMaintenanceNotice { }
    function Get-CIPPLegacyInfrastructureNotice { }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-CippAccessRole { param($Request) 'readonly' }
    function Assert-CippVersion { param($CIPPVersion) }
    function Sync-CippContainerUpdateState { }
    function Write-LogMessage { param($message, $API, $tenant, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-GetCippAlerts.ps1')
    $script:Request = [pscustomobject]@{ Query = [pscustomobject]@{ localversion = '10.0.0' } }
}

Describe 'Invoke-GetCippAlerts update notice' {
    BeforeEach {
        $script:OriginalNG = $env:CIPPNG
        $script:OriginalTz = $env:CIPP_TIMEZONE
        $env:CIPPNG = 'true'
        $env:CIPP_TIMEZONE = 'Europe/Amsterdam'
        Mock Assert-CippVersion { [pscustomobject]@{ OutOfDateCIPP = $false; OutOfDateCIPPAPI = $true } }
        Mock Write-LogMessage { }
    }
    AfterEach { $env:CIPPNG = $script:OriginalNG; $env:CIPP_TIMEZONE = $script:OriginalTz }

    It 'names the scheduled restart time in the banner and the logbook when the container updates itself' {
        Mock Sync-CippContainerUpdateState { [pscustomobject]@{ AutoUpdate = 'true'; CheckInterval = '1h'; CheckTime = '23' } }
        $Alert = (Invoke-GetCippAlerts -Request $script:Request).Body | Where-Object { $_.title -eq 'CIPP API Out of Date' }
        $Alert.Alert | Should -Match "scheduled restart time, 23:00 \(Europe/Amsterdam\)"
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Alert' -and $message -like "*scheduled restart time, 23:00 (Europe/Amsterdam)*" }
    }

    It 'keeps asking for an update when auto-restart is off or no restart time is set' {
        foreach ($Settings in @(
                [pscustomobject]@{ AutoUpdate = 'false'; CheckInterval = '1h'; CheckTime = '23' }
                [pscustomobject]@{ AutoUpdate = 'true'; CheckInterval = '1h'; CheckTime = '' }
                [pscustomobject]@{ AutoUpdate = 'true'; CheckInterval = '0'; CheckTime = '23' }
            )) {
            $script:Settings = $Settings
            Mock Sync-CippContainerUpdateState { $script:Settings }
            $Alert = (Invoke-GetCippAlerts -Request $script:Request).Body | Where-Object { $_.title -eq 'CIPP API Out of Date' }
            $Alert.Alert | Should -Match 'Please update to the latest version\.'
        }
    }

    It 'does not read the container schedule outside a container instance' {
        $env:CIPPNG = $null
        Mock Sync-CippContainerUpdateState { throw 'should not be called' }
        $Alert = (Invoke-GetCippAlerts -Request $script:Request).Body | Where-Object { $_.title -eq 'CIPP API Out of Date' }
        $Alert.Alert | Should -Match 'Please update to the latest version\.'
        Should -Invoke Sync-CippContainerUpdateState -Times 0
    }
}

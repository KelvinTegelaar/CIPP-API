BeforeAll {
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $accelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPTable { param($TableName) @{} }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:SavedConfig = $Entity.config | ConvertFrom-Json }
    function Add-AzDataTableEntity { param($Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Register-CIPPExtensionScheduledTasks {
        param([switch]$Reschedule, $NextSync, $Extensions)
        if ($null -eq $script:SavedConfig) { throw 'Configuration must be saved before scheduling.' }
        $script:ScheduleCalls += @{ Reschedule = $Reschedule.IsPresent; NextSync = $NextSync; Extensions = $Extensions }
    }
    . "$PSScriptRoot/../../Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Extensions/Invoke-ExecExtensionsConfig.ps1"
}

Describe 'Extension configuration save ordering' {
    BeforeEach {
        $script:SavedConfig = $null
        $script:ScheduleCalls = @()
        $request = @{
            Params = @{ CIPPEndpoint = 'ExecExtensionsConfig' }
            Headers = @{ 'x-ms-original-url' = 'http://localhost:4280/api/ExecExtensionsConfig' }
            Body = [PSCustomObject]@{ Hudu = [PSCustomObject]@{ Enabled = $true; APIKey = 'SentToKeyVault'; IncludeLAPS = $true; NextSync = 1800000000 } }
        }
    }
    It 'persists first-time Hudu settings before rescheduling and registers other extensions' {
        $response = Invoke-ExecExtensionsConfig -Request $request
        $response.Body.Results | Should -BeLike 'Successfully saved*'
        $script:SavedConfig.Hudu.Enabled | Should -BeTrue
        $script:SavedConfig.Hudu.IncludeLAPS | Should -BeTrue
        $script:SavedConfig.Hudu.NextSync | Should -Be ''
        $script:ScheduleCalls.Count | Should -Be 2
        $script:ScheduleCalls[0].Reschedule | Should -BeTrue
        $script:ScheduleCalls[0].NextSync | Should -Be 1800000000
        $script:ScheduleCalls[0].Extensions | Should -Be 'Hudu'
        $script:ScheduleCalls[1].Reschedule | Should -BeFalse
    }
    It 'registers normal schedules after saving when no next-sync time is provided' {
        $request.Body.Hudu.NextSync = ''
        $response = Invoke-ExecExtensionsConfig -Request $request
        $response.Body.Results | Should -BeLike 'Successfully saved*'
        $script:ScheduleCalls.Count | Should -Be 1
        $script:ScheduleCalls[0].Reschedule | Should -BeFalse
    }
}

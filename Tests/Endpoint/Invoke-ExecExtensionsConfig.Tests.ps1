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
    function Set-ExtensionAPIKey { param($Extension, $APIKey) $script:KeyWrites.Add($Extension) }
    function Initialize-NinjaOneCredentialField { param($Configuration) $script:InitCalls.Add($Configuration) }
    . "$PSScriptRoot/../../Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Extensions/Invoke-ExecExtensionsConfig.ps1"
}

Describe 'NinjaOne credential fields on save' {
    BeforeEach {
        $script:SavedConfig = $null
        $script:ScheduleCalls = @()
        $script:InitCalls = [System.Collections.Generic.List[object]]::new()
        $request = @{
            Params  = @{ CIPPEndpoint = 'ExecExtensionsConfig' }
            Headers = @{ 'x-ms-original-url' = 'http://localhost:4280/api/ExecExtensionsConfig' }
            Body    = [PSCustomObject]@{ NinjaOne = [PSCustomObject]@{ Enabled = $true; Instance = 'eu.ninjarmm.com'; APIKey = 'SentToKeyVault'; IncludeLAPS = $true; IncludeBitLocker = $false } }
        }
    }
    It 'creates or adopts the credential fields from the saved configuration when a switch is on' {
        $response = Invoke-ExecExtensionsConfig -Request $request
        $response.Body.Results | Should -BeLike 'Successfully saved*'
        $script:InitCalls.Count | Should -Be 1
        $script:InitCalls[0].IncludeLAPS | Should -BeTrue
        $script:InitCalls[0].APIKey | Should -Be 'SentToKeyVault'
        $script:InitCalls[0].Instance | Should -Be 'eu.ninjarmm.com'
    }
    It 'leaves the fields alone when both switches are off' {
        $request.Body.NinjaOne.IncludeLAPS = $false
        $null = Invoke-ExecExtensionsConfig -Request $request
        $script:InitCalls.Count | Should -Be 0
    }
    It 'still saves and reports when NinjaOne cannot be reached' {
        Mock Initialize-NinjaOneCredentialField { throw 'token refused' }
        $response = Invoke-ExecExtensionsConfig -Request $request
        $response.StatusCode | Should -Be 200
        $response.Body.Results | Should -BeLike 'Successfully saved*token refused*'
        $script:SavedConfig.NinjaOne.IncludeLAPS | Should -BeTrue
    }
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

Describe 'Extension key storage only accepts known extension names' {
    BeforeEach {
        $script:SavedConfig = $null
        $script:ScheduleCalls = @()
        $script:InitCalls = [System.Collections.Generic.List[object]]::new()
        $script:KeyWrites = [System.Collections.Generic.List[string]]::new()
        $script:NewRequest = {
            param($Body)
            @{ Params = @{ CIPPEndpoint = 'ExecExtensionsConfig' }; Headers = @{ 'x-ms-original-url' = 'http://localhost:4280/api/ExecExtensionsConfig' }; Body = [PSCustomObject]$Body }
        }
    }

    It 'does not write a secret named <_>' -ForEach @('ApplicationSecret', 'ApplicationID', 'RefreshToken', 'TenantID', 'SAMCertificate', 'SSOAppId', '11111111-2222-3333-4444-555555555555', 'hudu ') {
        $response = Invoke-ExecExtensionsConfig -Request (& $script:NewRequest @{ $_ = [PSCustomObject]@{ APIKey = 'attacker-value' } })
        $script:KeyWrites.Count | Should -Be 0
        ($script:SavedConfig | ConvertTo-Json -Depth 5) | Should -Not -Match 'attacker-value'
    }

    It 'still stores the key for a known extension alongside an unknown name' {
        Invoke-ExecExtensionsConfig -Request (& $script:NewRequest @{ Hudu = [PSCustomObject]@{ APIKey = 'real-key'; BaseUrl = 'https://hudu.example' }; ApplicationSecret = [PSCustomObject]@{ APIKey = 'attacker-value' } }) | Out-Null
        $script:KeyWrites | Should -Be @('Hudu')
        $script:SavedConfig.Hudu.APIKey | Should -Be 'SentToKeyVault'
    }

    It 'accepts every extension the settings form can post' {
        $Extensions = Get-Content -LiteralPath "$PSScriptRoot/../../../frontend/src/data/Extensions.json" -Raw | ConvertFrom-Json
        $Names = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Extension in $Extensions) { $null = $Names.Add($Extension.id) }
        foreach ($Match in [regex]::Matches(($Extensions | ConvertTo-Json -Depth 20), '"name":\s*"([A-Za-z0-9]+)\.')) { $null = $Names.Add($Match.Groups[1].Value) }
        $Names.Count | Should -BeGreaterThan 10
        foreach ($Name in $Names) {
            $script:KeyWrites.Clear()
            Invoke-ExecExtensionsConfig -Request (& $script:NewRequest @{ $Name = [PSCustomObject]@{ APIKey = 'k' } }) | Out-Null
            $script:KeyWrites | Should -Be @($Name) -Because "$Name is in Extensions.json"
        }
    }
}

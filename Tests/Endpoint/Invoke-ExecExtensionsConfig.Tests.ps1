BeforeAll {
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $accelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    $script:StoredConfig = $null
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) if ($null -ne $script:StoredConfig) { @{ config = ($script:StoredConfig | ConvertTo-Json -Depth 10 -Compress) } } }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:SavedConfig = $Entity.config | ConvertFrom-Json }
    function Add-AzDataTableEntity { param($Entity, [switch]$Force) }
    $script:Logs = [System.Collections.Generic.List[object]]::new()
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) $script:Logs.Add([pscustomobject]@{ Message = $message; Sev = $Sev; LogData = $LogData }) }
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
        $script:StoredConfig = @{ NinjaOne = @{ Instance = 'eu.ninjarmm.com'; APIKey = 'SentToKeyVault' } }
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
        $script:StoredConfig = @{ Hudu = @{ APIKey = 'SentToKeyVault' } }
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
        $script:StoredConfig = $null
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

Describe 'A stored secret does not follow a changed destination' {
    BeforeEach {
        $script:SavedConfig = $null
        $script:ScheduleCalls = @()
        $script:InitCalls = [System.Collections.Generic.List[object]]::new()
        $script:KeyWrites = [System.Collections.Generic.List[string]]::new()
        $script:Logs.Clear()
        $script:StoredConfig = @{
            HaloPSA  = @{ Enabled = $true; ResourceURL = 'https://contoso.halopsa.com/api'; AuthURL = 'https://contoso.halopsa.com/auth'; ClientID = 'c'; APIKey = 'SentToKeyVault' }
            Hudu     = @{ Enabled = $true; BaseUrl = 'https://hudu.contoso.com'; APIKey = 'SentToKeyVault'; CFEnabled = $false }
            CFZTNA   = @{ Enabled = $true; ClientID = 'cf'; APIKey = 'SentToKeyVault' }
            PWPush   = @{ Enabled = $true; BaseUrl = 'https://pwpush.contoso.com'; UseBearerAuth = $false; APIKey = '' }
            Syncro   = @{ Enabled = $false; Subdomain = 'contoso'; APIKey = 'SentToKeyVault' }
            NinjaOne = @{ Enabled = $false; Instance = 'eu.ninjarmm.com'; APIKey = 'SentToKeyVault' }
        }
        # The settings page posts back everything it loaded, with SentToKeyVault for untouched secrets.
        $script:Post = {
            param([scriptblock]$Change)
            $Body = $script:StoredConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            & $Change $Body
            Invoke-ExecExtensionsConfig -Request @{ Params = @{ CIPPEndpoint = 'ExecExtensionsConfig' }; Headers = @{ 'x-ms-original-url' = 'https://cipp.contoso.com/api/ExecExtensionsConfig' }; Body = $Body }
        }
    }

    It 'saves a non-address change without re-entering the secret' {
        $response = & $script:Post { param($b) $b.HaloPSA.ClientID = 'new-client' }
        $response.StatusCode | Should -Be 200
        $script:SavedConfig.HaloPSA.ClientID | Should -Be 'new-client'
    }

    It 'ignores case and a trailing slash in an unchanged address' {
        $response = & $script:Post { param($b) $b.Hudu.BaseUrl = 'https://HUDU.contoso.com/' }
        $response.StatusCode | Should -Be 200
    }

    It 'refuses <Name> when the address changes and the secret is <Key>' -ForEach @(
        @{ Name = 'HaloPSA AuthURL'; Key = 'SentToKeyVault'; Change = { param($b) $b.HaloPSA.AuthURL = 'https://attacker.invalid/auth' } }
        @{ Name = 'HaloPSA AuthURL'; Key = 'blank'; Change = { param($b) $b.HaloPSA.AuthURL = 'https://attacker.invalid/auth'; $b.HaloPSA.APIKey = '' } }
        @{ Name = 'HaloPSA ResourceURL'; Key = 'SentToKeyVault'; Change = { param($b) $b.HaloPSA.ResourceURL = 'https://attacker.invalid/api' } }
        @{ Name = 'Hudu BaseUrl'; Key = 'SentToKeyVault'; Change = { param($b) $b.Hudu.BaseUrl = 'https://attacker.invalid' } }
        @{ Name = 'Syncro Subdomain'; Key = 'SentToKeyVault'; Change = { param($b) $b.Syncro.Subdomain = 'attacker.invalid#' } }
        @{ Name = 'NinjaOne Instance'; Key = 'SentToKeyVault'; Change = { param($b) $b.NinjaOne.Instance = 'app.ninjarmm.com' } }
    ) {
        $response = & $script:Post $Change
        $response.StatusCode | Should -Be 400
        $script:SavedConfig | Should -BeNullOrEmpty
        $script:KeyWrites.Count | Should -Be 0
    }

    It 'refuses when the stored block was dropped by an earlier save' {
        $script:StoredConfig.Remove('Hudu')
        $response = & $script:Post { param($b) $b | Add-Member -NotePropertyName Hudu -NotePropertyValue ([pscustomobject]@{ Enabled = $true; BaseUrl = 'https://attacker.invalid'; APIKey = 'SentToKeyVault' }) }
        $response.StatusCode | Should -Be 400
        $script:SavedConfig | Should -BeNullOrEmpty
    }

    It 'saves an address change when the secret is entered again' {
        $response = & $script:Post { param($b) $b.HaloPSA.AuthURL = 'https://new.halopsa.com/auth'; $b.HaloPSA.APIKey = 'new-secret' }
        $response.StatusCode | Should -Be 200
        $script:KeyWrites | Should -Be @('HaloPSA')
        $script:SavedConfig.HaloPSA.AuthURL | Should -Be 'https://new.halopsa.com/auth'
    }

    It 'refuses a changed address that is not https' {
        $response = & $script:Post { param($b) $b.HaloPSA.AuthURL = 'http://new.halopsa.com/auth'; $b.HaloPSA.APIKey = 'new-secret' }
        $response.StatusCode | Should -Be 400
        $script:KeyWrites.Count | Should -Be 0
    }

    It 'requires the Cloudflare secret when a Hudu address change would carry it' {
        $script:StoredConfig.Hudu.CFEnabled = $true
        $response = & $script:Post { param($b) $b.Hudu.BaseUrl = 'https://attacker.invalid'; $b.Hudu.APIKey = 'any-key' }
        $response.StatusCode | Should -Be 400
        $response.Body.Results | Should -Match 'CFZTNA'
    }

    It 'turns on Cloudflare Access for an unchanged Hudu address without a new key' {
        $response = & $script:Post { param($b) $b.Hudu.CFEnabled = $true }
        $response.StatusCode | Should -Be 200
        $script:SavedConfig.Hudu.CFEnabled | Should -BeTrue
    }

    It 'lets an anonymous PWPush move without a key' {
        $response = & $script:Post { param($b) $b.PWPush.BaseUrl = 'https://pwpush2.contoso.com' }
        $response.StatusCode | Should -Be 200
    }

    It 'requires a new PWPush key when bearer auth is switched on' {
        $response = & $script:Post { param($b) $b.PWPush.UseBearerAuth = $true }
        $response.StatusCode | Should -Be 400
        $script:SavedConfig | Should -BeNullOrEmpty
    }

    It 'switches on PWPush bearer auth when a new key is entered' {
        $response = & $script:Post { param($b) $b.PWPush.UseBearerAuth = $true; $b.PWPush.APIKey = 'new-key' }
        $response.StatusCode | Should -Be 200
        $script:KeyWrites | Should -Be @('PWPush')
    }

    It 'requires the PWPush key when the address moves with bearer auth on' {
        $script:StoredConfig.PWPush.UseBearerAuth = $true
        $response = & $script:Post { param($b) $b.PWPush.BaseUrl = 'https://attacker.invalid' }
        $response.StatusCode | Should -Be 400
    }

    It 'refuses a NinjaOne instance outside the allowed hosts even with a new key, enabled or not' -ForEach @($true, $false) {
        $Enabled = $_
        $response = & $script:Post { param($b) $b.NinjaOne.Enabled = $Enabled; $b.NinjaOne.Instance = 'attacker.invalid'; $b.NinjaOne.APIKey = 'new-secret' }.GetNewClosure()
        $response.StatusCode | Should -Be 400
        $script:SavedConfig | Should -BeNullOrEmpty
        $script:KeyWrites.Count | Should -Be 0
    }

    It 'lets other settings save when a disabled NinjaOne still holds an old instance value nobody changed' {
        $script:StoredConfig.NinjaOne.Instance = 'app.ninjarmm.com/v2'
        $response = & $script:Post { param($b) $b.HaloPSA.ClientID = 'new-client' }
        $response.StatusCode | Should -Be 200
        $script:SavedConfig.HaloPSA.ClientID | Should -Be 'new-client'
    }

    It 'logs each changed setting with its old and new value' {
        $null = & $script:Post { param($b) $b.HaloPSA.ClientID = 'new-client'; $b.Hudu.CFEnabled = $true }
        $Entry = $script:Logs | Where-Object Sev -EQ 'Info' | Select-Object -Last 1
        $Entry.Message | Should -BeLike '*HaloPSA (ClientID)*'
        $Entry.Message | Should -BeLike '*Hudu (CFEnabled)*'
        $Entry.LogData.Count | Should -Be 2
        $Entry.LogData['HaloPSA.ClientID'] | Should -Be 'c -> new-client'
        $Entry.LogData['Hudu.CFEnabled'] | Should -Be 'False -> True'
    }

    It 'logs that a new key was entered without logging the key' {
        $null = & $script:Post { param($b) $b.HaloPSA.AuthURL = 'https://new.halopsa.com/auth'; $b.HaloPSA.APIKey = 'super-secret-value' }
        $Entry = $script:Logs | Where-Object Sev -EQ 'Info' | Select-Object -Last 1
        ($Entry | ConvertTo-Json -Depth 6) | Should -Not -Match 'super-secret-value'
        $Entry.LogData['HaloPSA.APIKey'] | Should -Be 'new key entered'
        $Entry.LogData['HaloPSA.AuthURL'] | Should -Be 'https://contoso.halopsa.com/auth -> https://new.halopsa.com/auth'
    }

    It 'logs no change list when nothing changed' {
        $null = & $script:Post { param($b) }
        $Entry = $script:Logs | Where-Object Sev -EQ 'Info' | Select-Object -Last 1
        $Entry.Message | Should -BeLike 'Successfully saved*'
        $Entry.Message | Should -Not -BeLike '*Changed*'
        $Entry.LogData | Should -BeNullOrEmpty
    }

    It 'logs the attempted change when a save is refused' {
        $null = & $script:Post { param($b) $b.Hudu.BaseUrl = 'https://attacker.invalid' }
        $Entry = $script:Logs | Where-Object Sev -EQ 'Warning' | Select-Object -Last 1
        $Entry.LogData['Hudu.BaseUrl'] | Should -Be 'https://hudu.contoso.com -> https://attacker.invalid'
    }

    It 'refuses the save when that old instance value is on an enabled NinjaOne' {
        $script:StoredConfig.NinjaOne.Instance = 'app.ninjarmm.com/v2'
        $response = & $script:Post { param($b) $b.NinjaOne.Enabled = $true }
        $response.StatusCode | Should -Be 400
        $script:SavedConfig | Should -BeNullOrEmpty
    }
}

Describe 'External CSP validation on save' {
    BeforeEach {
        $script:SavedConfig = $null
        $script:StoredConfig = $null
        $script:ScheduleCalls = @()
        $script:InitCalls = [System.Collections.Generic.List[object]]::new()
        $script:KeyWrites = [System.Collections.Generic.List[string]]::new()
        $script:ExternalCsp = [PSCustomObject]@{
            Enabled          = $true
            APIKey           = 'vendor-secret'
            TestUrl          = 'https://vendor.example/test'
            CatalogUrl       = 'https://vendor.example/catalog'
            SubscriptionsUrl = 'https://vendor.example/subscriptions'
            OrderUrl         = 'https://vendor.example/orders'
            QuantityUrl      = 'https://vendor.example/quantity'
            CancelUrl        = 'https://vendor.example/cancel'
        }
        $script:NewRequest = {
            param($Body)
            @{
                Params  = @{ CIPPEndpoint = 'ExecExtensionsConfig' }
                Headers = @{ 'x-ms-original-url' = 'http://localhost:4280/api/ExecExtensionsConfig' }
                Body    = $Body
            }
        }
    }
    It 'saves a complete External CSP configuration and stores its secret' {
        $response = Invoke-ExecExtensionsConfig -Request (& $script:NewRequest ([PSCustomObject]@{ ExternalCSP = $script:ExternalCsp }))
        $response.Body.Results | Should -BeLike 'Successfully saved*'
        $script:SavedConfig.ExternalCSP.OrderUrl | Should -Be 'https://vendor.example/orders'
        $script:SavedConfig.ExternalCSP.APIKey | Should -Be 'SentToKeyVault'
        $script:KeyWrites | Should -Be @('ExternalCSP')
    }
    It 'refuses to enable External CSP alongside Sherweb and saves nothing' {
        $Body = [PSCustomObject]@{ ExternalCSP = $script:ExternalCsp; Sherweb = [PSCustomObject]@{ Enabled = $true; APIKey = 'SentToKeyVault' } }
        $response = Invoke-ExecExtensionsConfig -Request (& $script:NewRequest $Body)
        [int]$response.StatusCode | Should -Be 400
        $response.Body.Results | Should -BeLike '*cannot both be enabled*'
        $script:SavedConfig | Should -BeNullOrEmpty
    }
    It 'refuses a vendor URL that is not https and saves nothing' {
        $script:ExternalCsp.CancelUrl = 'http://vendor.example/cancel'
        $response = Invoke-ExecExtensionsConfig -Request (& $script:NewRequest ([PSCustomObject]@{ ExternalCSP = $script:ExternalCsp }))
        [int]$response.StatusCode | Should -Be 400
        $response.Body.Results | Should -BeLike '*CancelUrl must be an https URL*'
        $script:SavedConfig | Should -BeNullOrEmpty
    }
    It 'refuses an enabled configuration with a URL missing' {
        $script:ExternalCsp.TestUrl = ''
        $response = Invoke-ExecExtensionsConfig -Request (& $script:NewRequest ([PSCustomObject]@{ ExternalCSP = $script:ExternalCsp }))
        [int]$response.StatusCode | Should -Be 400
        $response.Body.Results | Should -BeLike '*TestUrl must be an https URL*'
    }
    It 'does not send the stored secret to a changed vendor URL' {
        $script:StoredConfig = @{ ExternalCSP = @{ Enabled = $true; APIKey = 'SentToKeyVault'; TestUrl = 'https://vendor.example/test'; CatalogUrl = 'https://vendor.example/catalog'; SubscriptionsUrl = 'https://vendor.example/subscriptions'; OrderUrl = 'https://vendor.example/orders'; QuantityUrl = 'https://vendor.example/quantity'; CancelUrl = 'https://vendor.example/cancel' } }
        $script:ExternalCsp.APIKey = 'SentToKeyVault'
        $script:ExternalCsp.OrderUrl = 'https://attacker.invalid/orders'
        $response = Invoke-ExecExtensionsConfig -Request (& $script:NewRequest ([PSCustomObject]@{ ExternalCSP = $script:ExternalCsp }))
        [int]$response.StatusCode | Should -Be 400
        $response.Body.Results | Should -BeLike '*Enter a new ExternalCSP API key*'
        $script:SavedConfig | Should -BeNullOrEmpty
    }
    It 'saves an unchanged configuration without re-entering the secret' {
        $script:StoredConfig = @{ ExternalCSP = @{ Enabled = $true; APIKey = 'SentToKeyVault'; TestUrl = 'https://vendor.example/test'; CatalogUrl = 'https://vendor.example/catalog'; SubscriptionsUrl = 'https://vendor.example/subscriptions'; OrderUrl = 'https://vendor.example/orders'; QuantityUrl = 'https://vendor.example/quantity'; CancelUrl = 'https://vendor.example/cancel' } }
        $script:ExternalCsp.APIKey = 'SentToKeyVault'
        $script:ExternalCsp | Add-Member -NotePropertyName AuthHeaderName -NotePropertyValue 'x-vendor-key'
        $response = Invoke-ExecExtensionsConfig -Request (& $script:NewRequest ([PSCustomObject]@{ ExternalCSP = $script:ExternalCsp }))
        [int]$response.StatusCode | Should -Be 200
        $script:SavedConfig.ExternalCSP.AuthHeaderName | Should -Be 'x-vendor-key'
        $script:KeyWrites.Count | Should -Be 0
    }
}

Write-Information '#### CIPP-API Start ####'

$Timings = @{}
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$env:CIPPRootPath = $PSScriptRoot

# Test Proxyman CA certificate into trusted store if present (for local dev HTTPS inspection)
$ProxymanCert = Join-Path $env:CIPPRootPath 'proxyman.pem'
if (Test-Path $ProxymanCert) {
    $SwProxyman = [System.Diagnostics.Stopwatch]::StartNew()
    # Verify the cert is trusted in the system store
    try {
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ProxymanCert)
        $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $trusted = $chain.Build($cert)
        if ($trusted) {
            Write-Information 'Proxyman CA certificate is trusted.'
        } else {
            $chainStatus = $chain.ChainStatus | ForEach-Object { $_.StatusInformation.Trim() }
            Write-Warning "Proxyman CA certificate is NOT trusted: $($chainStatus -join '; ')"
        }
    } catch {
        Write-Warning "Failed to verify Proxyman CA certificate trust: $($_.Exception.Message)"
    }
    $SwProxyman.Stop()
    $Timings['ProxymanCertCheck'] = $SwProxyman.Elapsed.TotalMilliseconds
}

# Only load Application Insights SDK for telemetry if a connection string or instrumentation key is set
$hasAppInsights = $false
if ($env:APPLICATIONINSIGHTS_CONNECTION_STRING -or $env:APPINSIGHTS_INSTRUMENTATIONKEY) {
    $hasAppInsights = $true
}
if ($hasAppInsights) {
    $SwAppInsights = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $AppInsightsDllPath = Join-Path $env:CIPPRootPath 'Shared\AppInsights\Microsoft.ApplicationInsights.dll'
        $null = [Reflection.Assembly]::LoadFile($AppInsightsDllPath)
        Write-Debug 'Application Insights SDK loaded successfully'
    } catch {
        Write-Warning "Failed to load Application Insights SDK: $($_.Exception.Message)"
    }
    $SwAppInsights.Stop()
    $Timings['AppInsightsSDK'] = $SwAppInsights.Elapsed.TotalMilliseconds
}

# Import core modules
$SwCoreModules = [System.Diagnostics.Stopwatch]::StartNew()
$ModulesPath = Join-Path $env:CIPPRootPath 'Modules'
$Modules = @('CIPPCore', 'CippExtensions', 'AzBobbyTables')
foreach ($Module in $Modules) {
    $SwModule = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Import-Module -Name (Join-Path $ModulesPath $Module) -ErrorAction Stop
        $SwModule.Stop()
        $Timings["Module_$Module"] = $SwModule.Elapsed.TotalMilliseconds
    } catch {
        $SwModule.Stop()
        $Timings["Module_$Module"] = $SwModule.Elapsed.TotalMilliseconds
        Write-LogMessage -message "Failed to import module - $Module" -LogData (Get-CippException -Exception $_) -Sev 'debug'
        Write-Error $_.Exception.Message
    }
}
$SwCoreModules.Stop()
$Timings['CoreModules'] = $SwCoreModules.Elapsed.TotalMilliseconds

# Load CIPPSharp assembly once at startup for all worker types
$SwCIPPSharp = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $CIPPSharpDllPath = Join-Path $env:CIPPRootPath 'Shared\CIPPSharp\bin\CIPPSharp.dll'
    if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies().Location -contains $CIPPSharpDllPath)) {
        $null = [Reflection.Assembly]::LoadFile($CIPPSharpDllPath)
    }
} catch {
    Write-Warning "CIPPSharp failed to load: $($_.Exception.Message)"
}
$SwCIPPSharp.Stop()
$Timings['CIPPSharp'] = $SwCIPPSharp.Elapsed.TotalMilliseconds

# Pre-load function permissions cache once per worker startup (fallback remains in runtime code)
$SwPermissionsPreload = [System.Diagnostics.Stopwatch]::StartNew()
if (-not $global:CIPPFunctionPermissions) {
    try {
        $PermissionsFileJson = Join-Path $env:CIPPRootPath 'Config' 'function-permissions.json'
        if (Test-Path $PermissionsFileJson) {
            $global:CIPPFunctionPermissions = [System.IO.File]::ReadAllText($PermissionsFileJson) | ConvertFrom-Json -AsHashtable
            Write-Debug "Preloaded $($global:CIPPFunctionPermissions.Count) function permissions from JSON cache"
        } else {
            Write-Debug "Function permissions cache file not found at '$PermissionsFileJson'; runtime fallback will apply"
        }
    } catch {
        Write-Warning "Failed to preload function permissions from JSON cache: $($_.Exception.Message)"
    }
}
$SwPermissionsPreload.Stop()
$Timings['PermissionsPreload'] = $SwPermissionsPreload.Elapsed.TotalMilliseconds

# Initialize global TelemetryClient only if Application Insights is configured
if ($hasAppInsights -and -not $global:TelemetryClient) {
    $SwTelemetry = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $connectionString = $env:APPLICATIONINSIGHTS_CONNECTION_STRING
        if ($connectionString) {
            # Use connection string (preferred method)
            $config = [Microsoft.ApplicationInsights.Extensibility.TelemetryConfiguration]::CreateDefault()
            $config.ConnectionString = $connectionString
            $global:TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new($config)
            Enable-CippConsoleLogging
            Write-Debug 'TelemetryClient initialized with connection string'
        } elseif ($env:APPINSIGHTS_INSTRUMENTATIONKEY) {
            # Fall back to instrumentation key
            $global:TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new()
            $global:TelemetryClient.InstrumentationKey = $env:APPINSIGHTS_INSTRUMENTATIONKEY
            Enable-CippConsoleLogging
            Write-Debug 'TelemetryClient initialized with instrumentation key'
        }
    } catch {
        Write-Warning "Failed to initialize TelemetryClient: $($_.Exception.Message)"
    }
    $SwTelemetry.Stop()
    $Timings['TelemetryClient'] = $SwTelemetry.Elapsed.TotalMilliseconds
}

if ($env:ExternalDurablePowerShellSDK -eq $true) {
    $SwDurableSDK = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Import-Module AzureFunctions.PowerShell.Durable.SDK -ErrorAction Stop
        Write-Debug 'External Durable SDK enabled'
    } catch {
        Write-LogMessage -message 'Failed to import module - AzureFunctions.PowerShell.Durable.SDK' -LogData (Get-CippException -Exception $_) -Sev 'debug'
        $_.Exception.Message
    }
    $SwDurableSDK.Stop()
    $Timings['DurableSDK'] = $SwDurableSDK.Elapsed.TotalMilliseconds
}

$SwAuth = [System.Diagnostics.Stopwatch]::StartNew()
try {
    if (!$env:SetFromProfile) {
        Write-Debug "We're reloading from KV"
        $null = Get-CIPPAuthentication
    }
} catch {
    Write-LogMessage -message 'Could not retrieve keys from Keyvault' -LogData (Get-CippException -Exception $_) -Sev 'debug'
}
$SwAuth.Stop()
$Timings['Authentication'] = $SwAuth.Elapsed.TotalMilliseconds

$SwVersion = [System.Diagnostics.Stopwatch]::StartNew()
$CurrentVersion = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'version_latest.txt')).Trim()
$Table = Get-CippTable -tablename 'Version'
Write-Information "Function App: $($env:WEBSITE_SITE_NAME) | API Version: $CurrentVersion | PS Version: $($PSVersionTable.PSVersion)"
$env:CippVersion = $CurrentVersion

$LastStartup = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Version' and RowKey eq '$($env:WEBSITE_SITE_NAME)'" -Property @('PartitionKey', 'RowKey', 'Version') -First 1
if (!$LastStartup -or $CurrentVersion -ne $LastStartup.Version) {
    Write-Information "Version has changed from $($LastStartup.Version ?? 'None') to $CurrentVersion"
    if ($LastStartup) {
        $LastStartup.Version = $CurrentVersion
        Add-Member -InputObject $LastStartup -MemberType NoteProperty -Name 'PSVersion' -Value $PSVersionTable.PSVersion.ToString() -Force
    } else {
        $LastStartup = [PSCustomObject]@{
            PartitionKey = 'Version'
            RowKey       = $env:WEBSITE_SITE_NAME
            Version      = $CurrentVersion
            PSVersion    = $PSVersionTable.PSVersion.ToString()
        }
    }
    Update-AzDataTableEntity @Table -Entity $LastStartup -Force -ErrorAction SilentlyContinue
    try {
        Clear-CippDurables
    } catch {
        Write-LogMessage -message 'Failed to clear durables after update' -LogData (Get-CippException -Exception $_) -Sev 'Error'
    }

    try {
        $ReleaseTable = Get-CippTable -tablename 'cacheGitHubReleaseNotes'
        Remove-AzDataTableEntity @ReleaseTable -Entity @{ PartitionKey = 'GitHubReleaseNotes'; RowKey = 'GitHubReleaseNotes' } -ErrorAction SilentlyContinue
        Write-Debug 'Cleared GitHub release notes cache to force refresh on version update.'
    } catch {
        Write-Debug -Message 'Failed to clear GitHub release notes cache after update' -LogData (Get-CippException -Exception $_) -Sev 'Error'
    }
}
$SwVersion.Stop()
$Timings['VersionCheck'] = $SwVersion.Elapsed.TotalMilliseconds

if ($env:AzureWebJobsStorage -ne 'UseDevelopmentStorage=true' -and $env:NonLocalHostAzurite -ne 'true') {
    $SwOffloadSetup = [System.Diagnostics.Stopwatch]::StartNew()
    Set-CIPPEnvVarBackup
    Set-CIPPOffloadFunctionTriggers
    $SwOffloadSetup.Stop()
    $Timings['OffloadSetup'] = $SwOffloadSetup.Elapsed.TotalMilliseconds
}

$SwTimezone = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $TimeSettingsTable = Get-CIPPTable -tablename Config
    $TimeSettings = Get-CIPPAzDataTableEntity @TimeSettingsTable -Filter "PartitionKey eq 'TimeSettings' and RowKey eq 'TimeSettings'" -Property @('PartitionKey', 'RowKey', 'Timezone') -First 1
    if ($TimeSettings.Timezone) {
        # Validate before storing
        $null = [TimeZoneInfo]::FindSystemTimeZoneById($TimeSettings.Timezone)
        $env:CIPP_TIMEZONE = $TimeSettings.Timezone
        Write-Information "Timezone: $($TimeSettings.Timezone)"
    } else {
        $env:CIPP_TIMEZONE = 'UTC'
        Write-Information 'Timezone: UTC (default)'
    }
} catch {
    $env:CIPP_TIMEZONE = 'UTC'
    Write-Warning "Failed to load timezone from config, defaulting to UTC: $($_.Exception.Message)"
}
$SwTimezone.Stop()
$Timings['Timezone'] = $SwTimezone.Elapsed.TotalMilliseconds

# Import Extra modules if needed
$SwExtraModules = [System.Diagnostics.Stopwatch]::StartNew()
$ModulesPath = Join-Path $env:CIPPRootPath 'Modules'
$NonHttpModules = @('CIPPStandards', 'CIPPAlerts', 'CIPPTests', 'CIPPDB', 'CIPPActivityTriggers', 'DNSHealth')
$HttpModule = @('CIPPHTTP')

$HttpDisabled = $env:AzureWebJobs_CIPPHttpTrigger_Disabled -in @('true', '1') -or [System.Environment]::GetEnvironmentVariable('AzureWebJobs.CIPPHttpTrigger.Disabled') -in @('true', '1')
$QueueDisabled = $env:AzureWebJobs_CIPPQueueTrigger_Disabled -in @('true', '1') -or [System.Environment]::GetEnvironmentVariable('AzureWebJobs.CIPPQueueTrigger.Disabled') -in @('true', '1')
$OrchestratorDisabled = $env:AzureWebJobs_CIPPOrchestrator_Disabled -in @('true', '1') -or [System.Environment]::GetEnvironmentVariable('AzureWebJobs.CIPPOrchestrator.Disabled') -in @('true', '1')
$ActivityDisabled = $env:AzureWebJobs_CIPPActivityFunction_Disabled -in @('true', '1') -or [System.Environment]::GetEnvironmentVariable('AzureWebJobs.CIPPActivityFunction.Disabled') -in @('true', '1')
$TimerDisabled = $env:AzureWebJobs_CIPPTimer_Disabled -in @('true', '1') -or [System.Environment]::GetEnvironmentVariable('AzureWebJobs.CIPPTimer.Disabled') -in @('true', '1')

$AllNonHttpDisabled = $QueueDisabled -and $OrchestratorDisabled -and $ActivityDisabled -and $TimerDisabled

$WorkerType = if ($HttpDisabled) {
    'Offloaded'
} elseif ($AllNonHttpDisabled) {
    'HttpOnly'
} else {
    'Default'
}

$ModulesToImport = switch ($WorkerType) {
    'HttpOnly' { $HttpModule }
    'Offloaded' { $NonHttpModules }
    default { @($NonHttpModules + $HttpModule) }
}

Write-Debug "Worker type detected: $WorkerType"
Write-Debug "Modules to import: $($ModulesToImport -join ', ')"

foreach ($Module in $ModulesToImport) {
    $SwModule = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Import-Module -Name (Join-Path $ModulesPath $Module) -ErrorAction Stop
        $SwModule.Stop()
        $Timings["Module_$Module"] = $SwModule.Elapsed.TotalMilliseconds
    } catch {
        $SwModule.Stop()
        $Timings["Module_$Module"] = $SwModule.Elapsed.TotalMilliseconds
        Write-LogMessage -message "Failed to import module - $Module" -LogData (Get-CippException -Exception $_) -Sev 'debug'
        Write-Error $_.Exception.Message
    }
}

$SwExtraModules.Stop()
$Timings['ExtraModules'] = $SwExtraModules.Elapsed.TotalMilliseconds

# Load Cronos assembly once at startup for all but HttpOnly workers
if ($WorkerType -ne 'HttpOnly') {
    $SwCronos = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $CronosDllPath = Join-Path $env:CIPPRootPath 'Shared\Cronos\Cronos.dll'
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies().Location -contains $CronosDllPath)) {
            $null = [Reflection.Assembly]::LoadFile($CronosDllPath)
        }
    } catch {
        Write-Warning "Failed to load Cronos assembly: $($_.Exception.Message)"
    }
    $SwCronos.Stop()
    $Timings['CronosAssembly'] = $SwCronos.Elapsed.TotalMilliseconds
}

$TotalStopwatch.Stop()
$Timings['Total'] = $TotalStopwatch.Elapsed.TotalMilliseconds

Set-Location $env:CIPPRootPath

# Output timing summary as compressed JSON
$TimingsRounded = [ordered]@{}
foreach ($Key in ($Timings.Keys | Sort-Object)) {
    $TimingsRounded[$Key] = [math]::Round($Timings[$Key], 2)
}
Write-Debug "#### Profile Load Timings #### $($TimingsRounded | ConvertTo-Json -Compress)"

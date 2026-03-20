Write-Information '#### PROFILE START ####'
Write-Information "WEBSITE_DEPLOYMENT_ID: $($env:WEBSITE_DEPLOYMENT_ID)"
Write-Information "WEBSITE_SITE_NAME: $($env:WEBSITE_SITE_NAME)"
Write-Information "AzureWebJobsStorage present: $($null -ne $env:AzureWebJobsStorage)"
Write-Information "Derived KV name: $(($env:WEBSITE_DEPLOYMENT_ID -split '-')[0])"
Write-Information "PSScriptRoot: $PSScriptRoot"
Write-Information "#### PSModulePath: $($env:PSModulePath) ####"
Write-Information "#### Modules dir exists: $(Test-Path (Join-Path $PSScriptRoot 'Modules')) ####"
Write-Information "#### CIPPCore dir exists: $(Test-Path (Join-Path $PSScriptRoot 'Modules/CIPPCore')) ####"
Write-Information "#### AzBobbyTables dir exists: $(Test-Path (Join-Path $PSScriptRoot 'Modules/AzBobbyTables')) ####"
Write-Information "#### CippExtensions dir exists: $(Test-Path (Join-Path $PSScriptRoot 'Modules/CippExtensions')) ####"

Write-Information '#### CIPP-API Start ####'

$Timings = @{}
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Only load Application Insights SDK for telemetry if a connection string or instrumentation key is set
$hasAppInsights = $false
if ($env:APPLICATIONINSIGHTS_CONNECTION_STRING -or $env:APPINSIGHTS_INSTRUMENTATIONKEY) {
    $hasAppInsights = $true
}
Write-Information "#### AppInsights enabled: $hasAppInsights ####"

if ($hasAppInsights) {
    Set-Location -Path $PSScriptRoot
    $SwAppInsights = [System.Diagnostics.Stopwatch]::StartNew()
    $AppInsightsDllPath = Join-Path $PSScriptRoot 'Shared\AppInsights\Microsoft.ApplicationInsights.dll'
    Write-Information "#### AppInsights DLL path exists: $(Test-Path $AppInsightsDllPath) ####"
    try {
        $null = [Reflection.Assembly]::LoadFile($AppInsightsDllPath)
        Write-Information '#### AppInsights SDK loaded successfully ####'
    } catch {
        Write-Warning "Failed to load Application Insights SDK: $($_.Exception.Message)"
    }
    $SwAppInsights.Stop()
    $Timings['AppInsightsSDK'] = $SwAppInsights.Elapsed.TotalMilliseconds
}

# Import modules
Write-Information '#### Starting module imports ####'
$SwModules = [System.Diagnostics.Stopwatch]::StartNew()
$ModulesPath = Join-Path $PSScriptRoot 'Modules'
$Modules = @('CIPPCore', 'CippExtensions', 'AzBobbyTables')
foreach ($Module in $Modules) {
    $ModulePath = Join-Path $ModulesPath $Module
    Write-Information "#### Importing $Module from $ModulePath ####"
    Write-Information "#### $Module path exists: $(Test-Path $ModulePath) ####"
    $SwModule = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Import-Module -Name $ModulePath -ErrorAction Stop
        Write-Information "#### $Module imported successfully ####"
        $SwModule.Stop()
        $Timings["Module_$Module"] = $SwModule.Elapsed.TotalMilliseconds
    } catch {
        $SwModule.Stop()
        $Timings["Module_$Module"] = $SwModule.Elapsed.TotalMilliseconds
        Write-Information "#### $Module import FAILED: $($_.Exception.Message) ####"
        Write-Error $_.Exception.Message
    }
}
$SwModules.Stop()
$Timings['AllModules'] = $SwModules.Elapsed.TotalMilliseconds
Write-Information "#### All modules import complete. CIPPCore=$(Get-Module -Name CIPPCore -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) AzBobbyTables=$(Get-Module -Name AzBobbyTables -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) CippExtensions=$(Get-Module -Name CippExtensions -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) ####"

# Initialize global TelemetryClient only if Application Insights is configured
$SwTelemetry = [System.Diagnostics.Stopwatch]::StartNew()
if ($hasAppInsights -and -not $global:TelemetryClient) {
    Write-Information '#### Initializing TelemetryClient ####'
    try {
        $connectionString = $env:APPLICATIONINSIGHTS_CONNECTION_STRING
        if ($connectionString) {
            $config = [Microsoft.ApplicationInsights.Extensibility.TelemetryConfiguration]::CreateDefault()
            $config.ConnectionString = $connectionString
            $global:TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new($config)
            Enable-CippConsoleLogging
            Write-Information '#### TelemetryClient initialized with connection string ####'
        } elseif ($env:APPINSIGHTS_INSTRUMENTATIONKEY) {
            $global:TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new()
            $global:TelemetryClient.InstrumentationKey = $env:APPINSIGHTS_INSTRUMENTATIONKEY
            Enable-CippConsoleLogging
            Write-Information '#### TelemetryClient initialized with instrumentation key ####'
        }
    } catch {
        Write-Warning "Failed to initialize TelemetryClient: $($_.Exception.Message)"
    }
    $SwTelemetry.Stop()
    $Timings['TelemetryClient'] = $SwTelemetry.Elapsed.TotalMilliseconds
}

$SwDurableSDK = [System.Diagnostics.Stopwatch]::StartNew()
if ($env:ExternalDurablePowerShellSDK -eq $true) {
    Write-Information '#### Loading External Durable SDK ####'
    try {
        Import-Module AzureFunctions.PowerShell.Durable.SDK -ErrorAction Stop
        Write-Information '#### External Durable SDK loaded ####'
    } catch {
        Write-Information "#### DurableSDK import failed: $($_.Exception.Message) ####"
        $_.Exception.Message
    }
}
$SwDurableSDK.Stop()
$Timings['DurableSDK'] = $SwDurableSDK.Elapsed.TotalMilliseconds

$SwAuth = [System.Diagnostics.Stopwatch]::StartNew()
Write-Information "#### Before Auth - SetFromProfile: $($env:SetFromProfile) ####"
try {
    if (!$env:SetFromProfile) {
        Write-Information '#### Loading credentials from KeyVault ####'
        $Auth = Get-CIPPAuthentication
        Write-Information "#### Auth result: $Auth ####"
    } else {
        Write-Information '#### Skipping KV load - already set from profile ####'
    }
} catch {
    Write-Information "#### Auth exception: $($_.Exception.Message) ####"
}
$SwAuth.Stop()
$Timings['Authentication'] = $SwAuth.Elapsed.TotalMilliseconds

$SwVersion = [System.Diagnostics.Stopwatch]::StartNew()
Write-Information '#### Starting version check ####'
try {
    $CurrentVersion = (Get-Content -Path (Join-Path $PSScriptRoot 'version_latest.txt') -Raw).Trim()
    Write-Information "#### version_latest.txt read: $CurrentVersion ####"
} catch {
    Write-Information "#### Failed to read version_latest.txt: $($_.Exception.Message) ####"
    $CurrentVersion = 'Unknown'
}

Write-Information '#### Getting Version table ####'
try {
    $Table = Get-CippTable -tablename 'Version'
    Write-Information '#### Version table retrieved ####'
} catch {
    Write-Information "#### Failed to get Version table: $($_.Exception.Message) ####"
}

Write-Information "Function App: $($env:WEBSITE_SITE_NAME) | API Version: $CurrentVersion | PS Version: $($PSVersionTable.PSVersion)"
$env:CippVersion = $CurrentVersion

try {
    $LastStartup = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Version' and RowKey eq '$($env:WEBSITE_SITE_NAME)'"
    Write-Information "#### LastStartup retrieved: $($null -ne $LastStartup) ####"
} catch {
    Write-Information "#### Failed to get LastStartup: $($_.Exception.Message) ####"
}

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
    Write-Information '#### Before ClearDurables ####'
    try {
        Clear-CippDurables
        Write-Information '#### ClearDurables complete ####'
    } catch {
        Write-Information "#### ClearDurables failed: $($_.Exception.Message) ####"
    }

    try {
        $ReleaseTable = Get-CippTable -tablename 'cacheGitHubReleaseNotes'
        Remove-AzDataTableEntity @ReleaseTable -Entity @{ PartitionKey = 'GitHubReleaseNotes'; RowKey = 'GitHubReleaseNotes' } -ErrorAction SilentlyContinue
    } catch {
        Write-Information "#### Failed to clear release notes cache: $($_.Exception.Message) ####"
    }
}
$SwVersion.Stop()
$Timings['VersionCheck'] = $SwVersion.Elapsed.TotalMilliseconds

if ($env:AzureWebJobsStorage -ne 'UseDevelopmentStorage=true' -and $env:NonLocalHostAzurite -ne 'true') {
    Write-Information '#### Before EnvVarBackup ####'
    try {
        Set-CIPPEnvVarBackup
        Write-Information '#### EnvVarBackup complete ####'
    } catch {
        Write-Information "#### EnvVarBackup failed: $($_.Exception.Message) ####"
    }
    Write-Information '#### Before OffloadTriggers ####'
    try {
        Set-CIPPOffloadFunctionTriggers
        Write-Information '#### OffloadTriggers complete ####'
    } catch {
        Write-Information "#### OffloadTriggers failed: $($_.Exception.Message) ####"
    }
}

$TotalStopwatch.Stop()
$Timings['Total'] = $TotalStopwatch.Elapsed.TotalMilliseconds

$TimingsRounded = [ordered]@{}
foreach ($Key in ($Timings.Keys | Sort-Object)) {
    $TimingsRounded[$Key] = [math]::Round($Timings[$Key], 2)
}
Write-Information "#### Profile Load Timings: $($TimingsRounded | ConvertTo-Json -Compress) ####"
Write-Information '#### PROFILE COMPLETE ####'
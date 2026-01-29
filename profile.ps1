Write-Information '#### CIPP-API Start ####'

$Timings = @{}
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
# Only load Application Insights SDK for telemetry if a connection string or instrumentation key is set
$hasAppInsights = $false
if ($env:APPLICATIONINSIGHTS_CONNECTION_STRING -or $env:APPINSIGHTS_INSTRUMENTATIONKEY) {
    $hasAppInsights = $true
}
if ($hasAppInsights) {
    $SwAppInsights = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $AppInsightsDllPath = Join-Path $PSScriptRoot 'Shared\AppInsights\Microsoft.ApplicationInsights.dll'
        $null = [Reflection.Assembly]::LoadFile($AppInsightsDllPath)
        Write-Debug 'Application Insights SDK loaded successfully'
    } catch {
        Write-Warning "Failed to load Application Insights SDK: $($_.Exception.Message)"
    }
    $SwAppInsights.Stop()
    $Timings['AppInsightsSDK'] = $SwAppInsights.Elapsed.TotalMilliseconds
}

# Import modules
$SwModules = [System.Diagnostics.Stopwatch]::StartNew()
$ModulesPath = Join-Path $PSScriptRoot 'Modules'
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
$SwModules.Stop()
$Timings['AllModules'] = $SwModules.Elapsed.TotalMilliseconds

# Initialize global TelemetryClient only if Application Insights is configured
$SwTelemetry = [System.Diagnostics.Stopwatch]::StartNew()
if ($hasAppInsights -and -not $global:TelemetryClient) {
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

$SwDurableSDK = [System.Diagnostics.Stopwatch]::StartNew()
if ($env:ExternalDurablePowerShellSDK -eq $true) {
    try {
        Import-Module AzureFunctions.PowerShell.Durable.SDK -ErrorAction Stop
        Write-Debug 'External Durable SDK enabled'
    } catch {
        Write-LogMessage -message 'Failed to import module - AzureFunctions.PowerShell.Durable.SDK' -LogData (Get-CippException -Exception $_) -Sev 'debug'
        $_.Exception.Message
    }
}
$SwDurableSDK.Stop()
$Timings['DurableSDK'] = $SwDurableSDK.Elapsed.TotalMilliseconds

$SwAuth = [System.Diagnostics.Stopwatch]::StartNew()
try {
    if (!$env:SetFromProfile) {
        Write-Debug "We're reloading from KV"
        $Auth = Get-CIPPAuthentication
    }
} catch {
    Write-LogMessage -message 'Could not retrieve keys from Keyvault' -LogData (Get-CippException -Exception $_) -Sev 'debug'
}
$SwAuth.Stop()
$Timings['Authentication'] = $SwAuth.Elapsed.TotalMilliseconds

$SwVersion = [System.Diagnostics.Stopwatch]::StartNew()
$CurrentVersion = (Get-Content -Path (Join-Path $PSScriptRoot 'version_latest.txt') -Raw).Trim()
$Table = Get-CippTable -tablename 'Version'
Write-Information "Function App: $($env:WEBSITE_SITE_NAME) | API Version: $CurrentVersion | PS Version: $($PSVersionTable.PSVersion)"
$global:CippVersion = $CurrentVersion
$ENV:CurrentVersion = $CurrentVersion

$LastStartup = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Version' and RowKey eq '$($env:WEBSITE_SITE_NAME)'"
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

    $ReleaseTable = Get-CippTable -tablename 'cacheGitHubReleaseNotes'
    Remove-AzDataTableEntity @ReleaseTable -Entity @{ PartitionKey = 'GitHubReleaseNotes'; RowKey = 'GitHubReleaseNotes' } -ErrorAction SilentlyContinue
    Write-Debug 'Cleared GitHub release notes cache to force refresh on version update.'
}
$SwVersion.Stop()
$Timings['VersionCheck'] = $SwVersion.Elapsed.TotalMilliseconds

$TotalStopwatch.Stop()
$Timings['Total'] = $TotalStopwatch.Elapsed.TotalMilliseconds

# Output timing summary as compressed JSON
$TimingsRounded = [ordered]@{}
foreach ($Key in ($Timings.Keys | Sort-Object)) {
    $TimingsRounded[$Key] = [math]::Round($Timings[$Key], 2)
}
Write-Debug "#### Profile Load Timings #### $($TimingsRounded | ConvertTo-Json -Compress)"

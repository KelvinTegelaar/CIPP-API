Write-Information '#### CIPP-API Start ####'

# Load Application Insights SDK for telemetry
Set-Location -Path $PSScriptRoot
try {
    $AppInsightsDllPath = Join-Path $PSScriptRoot 'Shared\AppInsights\Microsoft.ApplicationInsights.dll'
    $null = [Reflection.Assembly]::LoadFile($AppInsightsDllPath)
    Write-Information 'Application Insights SDK loaded successfully'
} catch {
    Write-Warning "Failed to load Application Insights SDK: $($_.Exception.Message)"
}

# Import modules
$ModulesPath = Join-Path $PSScriptRoot 'Modules'
$Modules = @('CIPPCore', 'CippExtensions', 'Az.Accounts', 'Az.KeyVault', 'AzBobbyTables')
foreach ($Module in $Modules) {
    try {
        Import-Module -Name (Join-Path $ModulesPath $Module) -ErrorAction Stop
    } catch {
        Write-LogMessage -message "Failed to import module - $Module" -LogData (Get-CippException -Exception $_) -Sev 'debug'
        Write-Error $_.Exception.Message
    }
}

# Initialize global TelemetryClient
if (-not $global:TelemetryClient) {
    try {
        $connectionString = $env:APPLICATIONINSIGHTS_CONNECTION_STRING
        if ($connectionString) {
            # Use connection string (preferred method)
            $config = [Microsoft.ApplicationInsights.Extensibility.TelemetryConfiguration]::CreateDefault()
            $config.ConnectionString = $connectionString
            $global:TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new($config)
            Enable-CippConsoleLogging
            Write-Information 'TelemetryClient initialized with connection string'
        } elseif ($env:APPINSIGHTS_INSTRUMENTATIONKEY) {
            # Fall back to instrumentation key
            $global:TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new()
            $global:TelemetryClient.InstrumentationKey = $env:APPINSIGHTS_INSTRUMENTATIONKEY
            Enable-CippConsoleLogging
            Write-Information 'TelemetryClient initialized with instrumentation key'
        } else {
            Write-Warning 'No Application Insights connection string or instrumentation key found'
        }
    } catch {
        Write-Warning "Failed to initialize TelemetryClient: $($_.Exception.Message)"
    }
}

if ($env:ExternalDurablePowerShellSDK -eq $true) {
    try {
        Import-Module AzureFunctions.PowerShell.Durable.SDK -ErrorAction Stop
        Write-Information 'External Durable SDK enabled'
    } catch {
        Write-LogMessage -message 'Failed to import module - AzureFunctions.PowerShell.Durable.SDK' -LogData (Get-CippException -Exception $_) -Sev 'debug'
        $_.Exception.Message
    }
}

try {
    $null = Disable-AzContextAutosave -Scope Process
} catch {}

try {
    if (!$env:SetFromProfile) {
        Write-Information "We're reloading from KV"
        $Auth = Get-CIPPAuthentication
    }
} catch {
    Write-LogMessage -message 'Could not retrieve keys from Keyvault' -LogData (Get-CippException -Exception $_) -Sev 'debug'
}

$CurrentVersion = (Get-Content -Path (Join-Path $PSScriptRoot 'version_latest.txt') -Raw).Trim()
$Table = Get-CippTable -tablename 'Version'
Write-Information "Function App: $($env:WEBSITE_SITE_NAME) | API Version: $CurrentVersion | PS Version: $($PSVersionTable.PSVersion)"
$global:CippVersion = $CurrentVersion

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
    Write-Host 'Cleared GitHub release notes cache to force refresh on version update.'
}

# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.

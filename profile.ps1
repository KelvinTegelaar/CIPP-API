# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.

# Import modules
@('CIPPCore', 'CippExtensions', 'Az.KeyVault', 'Az.Accounts') | ForEach-Object {
    try {
        $Module = $_
        Import-Module -Name $_ -ErrorAction Stop
    } catch {
        Write-LogMessage -message "Failed to import module - $Module" -LogData (Get-CippException -Exception $_) -Sev 'debug'
        $_.Exception.Message
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
    Disable-AzContextAutosave -Scope Process | Out-Null
} catch {}

try {
    if (!$env:SetFromProfile) {
        Write-Information "We're reloading from KV"
        $Auth = Get-CIPPAuthentication
    }
} catch {
    Write-LogMessage -message 'Could not retrieve keys from Keyvault' -LogData (Get-CippException -Exception $_) -Sev 'debug'
}

Set-Location -Path $PSScriptRoot
$CurrentVersion = (Get-Content .\version_latest.txt).trim()
$Table = Get-CippTable -tablename 'Version'
Write-Information "Function: $($env:WEBSITE_SITE_NAME) Version: $CurrentVersion"
$LastStartup = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Version' and RowKey eq '$($env:WEBSITE_SITE_NAME)'"
if (!$LastStartup -or $CurrentVersion -ne $LastStartup.Version) {
    Write-Information "Version has changed from $($LastStartup.Version ?? 'None') to $CurrentVersion"
    if ($LastStartup) {
        $LastStartup.Version = $CurrentVersion
    } else {
        $LastStartup = [PSCustomObject]@{
            PartitionKey = 'Version'
            RowKey       = $env:WEBSITE_SITE_NAME
            Version      = $CurrentVersion
        }
    }
    Update-AzDataTableEntity @Table -Entity $LastStartup -Force
    try {
        Clear-CippDurables
    } catch {
        Write-LogMessage -message 'Failed to clear durables after update' -LogData (Get-CippException -Exception $_) -Sev 'Error'
    }
}
# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.

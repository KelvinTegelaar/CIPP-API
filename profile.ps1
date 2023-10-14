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
Import-Module .\GraphHelper.psm1
try {
    Import-Module Az.KeyVault -ErrorAction Stop
} catch { $_.Exception.Message }
try {
    Import-Module Az.Accounts
} catch { $_.Exception.Message }
Import-Module CippExtensions
Import-Module CippCore

try {
    Disable-AzContextAutosave -Scope Process | Out-Null
} catch {}

try {
    if (!$ENV:SetFromProfile) {
        Write-Host "We're reloading from KV"
        $Auth = Get-CIPPAuthentication
    }
} catch {
    Write-LogMessage -message "Could not retrieve keys from Keyvault: $($_.Exception.Message)" -Sev 'CRITICAL'
}

# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.
<#
.SYNOPSIS
    Regenerates the intuneCollection.json lookup file from the Microsoft Graph API.

.DESCRIPTION
    Queries the Microsoft Graph beta endpoint for all Intune device management
    configuration setting definitions and writes the result to intuneCollection.json
    in both the CIPP-API root and CIPP/src/data directories.

    The resulting file is used by Compare-CIPPIntuneObject.ps1 (backend) and
    CippTemplateFieldRenderer.jsx / CippJSONView.jsx (frontend) to translate
    raw settingDefinitionIds into human-readable display names.

    Must be run from the "Tools" folder in the CIPP-API project, with
    Initialize-DevEnvironment.ps1 already dot-sourced (or it will be loaded
    automatically). Requires a valid CIPP-managed TenantId to obtain a Graph token.

.PARAMETER TenantId
    A tenant domain or GUID that CIPP manages. Used only to obtain a Graph
    authentication token — the configurationSettings endpoint returns Microsoft's
    global catalog, not tenant-specific data.

.EXAMPLE
    # From the Tools folder, after initialising your dev environment:
    . .\Initialize-DevEnvironment.ps1
    .\Update-IntuneCollection.ps1 -TenantId contoso.onmicrosoft.com

.NOTES
    Permissions required: DeviceManagementConfiguration.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Ensure the CIPP module is loaded
# ---------------------------------------------------------------------------
if (-not (Get-Module -Name CIPPCore)) {
    Write-Host 'CIPPCore not loaded — running Initialize-DevEnvironment.ps1...' -ForegroundColor Yellow
    . (Join-Path $PSScriptRoot 'Initialize-DevEnvironment.ps1')
}

# ---------------------------------------------------------------------------
# Fetch all configurationSettings (New-GraphGetRequest auto-paginates)
# ---------------------------------------------------------------------------
Write-Host 'Fetching Intune configuration settings (this may take a while)...' -ForegroundColor Yellow

$allSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationSettings' -tenantid $TenantId -NoAuthCheck $true

Write-Host "Total settings fetched: $($allSettings.Count)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Transform to the shape expected by CIPP
# Shape: [{ id, displayName, options: [{id, displayName, description}] | null }]
# ---------------------------------------------------------------------------
Write-Host 'Transforming data...' -ForegroundColor Yellow

$collection = $allSettings | Sort-Object -Property id | ForEach-Object {
    $rawOptions = $_.PSObject.Properties['options']?.Value
    $options = if ($rawOptions -and $rawOptions.Count -gt 0) {
        $rawOptions | ForEach-Object {
            [PSCustomObject]@{
                id          = $_.PSObject.Properties['itemId']?.Value
                displayName = $_.PSObject.Properties['displayName']?.Value
                description = $_.PSObject.Properties['description']?.Value
            }
        }
    } else {
        $null
    }

    [PSCustomObject]@{
        id          = $_.id
        displayName = $_.displayName
        options     = $options
    }
}

# ---------------------------------------------------------------------------
# Write output files
# ---------------------------------------------------------------------------
Set-Location $PSScriptRoot

$json = $collection | ConvertTo-Json -Depth 5

# CIPP-API root (used by Compare-CIPPIntuneObject.ps1 at runtime)
$apiPath = Join-Path $PSScriptRoot '..\Config\intuneCollection.json'
$json | Set-Content -Path $apiPath -Encoding utf8NoBOM
Write-Host "Written: $(Resolve-Path $apiPath)" -ForegroundColor Green

# CIPP frontend src/data (used by the React UI)
$frontendPath = Join-Path $PSScriptRoot '..\..\CIPP\src\data\intuneCollection.json'
if (Test-Path (Split-Path $frontendPath)) {
    $json | Set-Content -Path $frontendPath -Encoding utf8NoBOM
    Write-Host "Written: $(Resolve-Path $frontendPath)" -ForegroundColor Green
} else {
    Write-Host "CIPP frontend path not found — skipping: $frontendPath" -ForegroundColor Yellow
    Write-Host "Copy $(Resolve-Path $apiPath) manually to your CIPP/src/data/ directory." -ForegroundColor Yellow
}

Write-Host "`nDone. $($collection.Count) settings written to intuneCollection.json." -ForegroundColor Green

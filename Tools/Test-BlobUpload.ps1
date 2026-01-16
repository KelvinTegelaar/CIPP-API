param(
    [Parameter(Mandatory = $false)] [string] $ContainerName = 'test',
    [Parameter(Mandatory = $false)] [string] $BlobName = 'hello.txt',
    [Parameter(Mandatory = $false)] [string] $Content = 'Hello, world!',
    [Parameter(Mandatory = $false)] [string] $ConnectionString = $env:AzureWebJobsStorage
)

$ErrorActionPreference = 'Stop'

# Import CIPPCore module from repository
$modulePath = Join-Path $PSScriptRoot '..' 'Modules' 'CIPPCore' 'CIPPCore.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "CIPPCore module not found at $modulePath"
}
Import-Module -Force $modulePath

if (-not $ConnectionString) {
    throw 'Azure Storage connection string not provided. Set AzureWebJobsStorage or pass -ConnectionString.'
}

# Parse connection string for AccountName and AccountKey
$connectionParams = @{}
foreach ($part in ($ConnectionString -split ';')) {
    $p = $part.Trim()
    if ($p -and $p -match '^(.+?)=(.+)$') { $connectionParams[$matches[1]] = $matches[2] }
}
$AccountName = $connectionParams['AccountName']
$AccountKey = $connectionParams['AccountKey']

# Support UseDevelopmentStorage=true
if ($connectionParams['UseDevelopmentStorage'] -eq 'true') {
    $AccountName = 'devstoreaccount1'
    $AccountKey = 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=='
}

if (-not $AccountName -or -not $AccountKey) {
    throw 'Connection string must contain AccountName and AccountKey or UseDevelopmentStorage=true.'
}

Write-Host "Account: $AccountName" -ForegroundColor Cyan
Write-Host "Container: $ContainerName" -ForegroundColor Cyan
Write-Host "Blob: $BlobName" -ForegroundColor Cyan

# Check if container exists via listing; create if missing
$containers = @()
try {
    $containers = New-CIPPAzStorageRequest -Service 'blob' -Component 'list'
} catch { $containers = @() }

$exists = ($containers | Where-Object { $_.Name -eq $ContainerName }) -ne $null
if ($exists) {
    Write-Host 'Container exists.' -ForegroundColor Green
} else {
    Write-Host 'Container not found. Creating...' -ForegroundColor Yellow
    $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $ContainerName -Method 'PUT' -QueryParams @{ restype = 'container' }
    Start-Sleep -Seconds 1
    # Re-check
    try {
        $containers = New-CIPPAzStorageRequest -Service 'blob' -Component 'list'
    } catch { $containers = @() }
    $exists = ($containers | Where-Object { $_.Name -eq $ContainerName }) -ne $null
    if (-not $exists) { throw "Failed to create container '$ContainerName'" }
    Write-Host 'Container created.' -ForegroundColor Green
}

# Upload blob content (BlockBlob by default)
Write-Host 'Uploading blob content...' -ForegroundColor Yellow
try {
    $null = New-CIPPAzStorageRequest -Service 'blob' -Resource "$ContainerName/$BlobName" -Method 'PUT' -ContentType 'text/plain; charset=utf-8' -Body $Content
} catch {
    Write-Error "Blob upload failed: $($_.Exception.Message)"
    throw
}
Write-Host 'Upload complete.' -ForegroundColor Green

# Generate SAS token valid for 7 days (read-only)
$expiry = (Get-Date).ToUniversalTime().AddDays(7)
$sas = New-CIPPAzServiceSAS -AccountName $AccountName -AccountKey $AccountKey -Service 'blob' -ResourcePath "$ContainerName/$BlobName" -Permissions 'r' -ExpiryTime $expiry -Protocol 'https' -Version '2022-11-02' -SignedResource 'b' -ConnectionString $ConnectionString

$url = $sas.ResourceUri + $sas.Token
Write-Host 'Download URL (7 days):' -ForegroundColor Cyan
Write-Output $url

# Return structured object
[PSCustomObject]@{ Url = $url; Container = $ContainerName; Blob = $BlobName; ExpiresUtc = $expiry }

param(
    [string]$ModulePath = (Join-Path $PSScriptRoot '..' 'Modules' 'CIPPHTTP'),
    [string]$OutputPath,
    [string]$ModuleName
)

$ErrorActionPreference = 'Stop'

function Resolve-ModuleImportPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $psd1 = Join-Path $Root "$Name.psd1"
    if (Test-Path $psd1) { return $psd1 }

    $psm1 = Join-Path $Root "$Name.psm1"
    if (Test-Path $psm1) { return $psm1 }

    throw "Module files not found for '$Name' in '$Root'. Expected $Name.psd1 or $Name.psm1."
}

function Get-HelpProperty {
    param(
        [Parameter(Mandatory = $true)]$HelpObject,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $property = $HelpObject.PSObject.Properties[$PropertyName]
    if ($property) { return $property.Value }
    return ''
}

function Get-HelpDescription {
    param(
        [Parameter(Mandatory = $true)]$HelpObject
    )

    $synopsis = (Get-HelpProperty -HelpObject $HelpObject -PropertyName 'Synopsis')
    if ($synopsis) {
        return ([string]$synopsis).Trim()
    }

    $description = Get-HelpProperty -HelpObject $HelpObject -PropertyName 'Description'
    if ($null -eq $description) {
        return ''
    }

    if ($description -is [string]) {
        return $description.Trim()
    }

    if ($description.PSObject.Properties['Text']) {
        return ([string]$description.Text).Trim()
    }

    if ($description.PSObject.Properties['para']) {
        $paragraphs = @($description.para | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        if ($paragraphs.Count -gt 0) {
            return ($paragraphs -join ' ').Trim()
        }
    }

    return ''
}

# Resolve defaults to CIPPCore where the cache file will live
$CIPPCorePath = (Join-Path $PSScriptRoot '..' 'Modules' 'CIPPCore')
if (-not (Test-Path -Path $CIPPCorePath)) {
    throw "CIPPCore '$CIPPCorePath' not found."
}
$CIPPCorePath = (Resolve-Path -Path $CIPPCorePath).ProviderPath

if (-not (Test-Path -Path $ModulePath)) {
    throw "ModulePath '$ModulePath' not found."
}
$ModulePath = (Resolve-Path -Path $ModulePath).ProviderPath

if (-not $ModuleName) { $ModuleName = (Split-Path -Path $ModulePath -Leaf) }
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot '..' 'Config' 'function-permissions.json'
}
$OutputPath = [System.IO.Path]::ChangeExtension($OutputPath, '.json')
$OutputDirectory = Split-Path -Parent $OutputPath

# Ensure destination directory exists
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force

# Import target module so Get-Help can read Role/Functionality metadata
$ModuleImportPath = Resolve-ModuleImportPath -Root $ModulePath -Name $ModuleName
$normalizedImportPath = [System.IO.Path]::GetFullPath($ModuleImportPath)
$loaded = Get-Module -Name $ModuleName | Where-Object { [System.IO.Path]::GetFullPath($_.Path) -eq $normalizedImportPath }
if (-not $loaded) {
    Write-Host "Importing module '$ModuleName' from '$ModuleImportPath'"
    Import-Module -Name $ModuleImportPath -Force -ErrorAction Stop
} else {
    Write-Host "Module '$ModuleName' already loaded from '$ModuleImportPath'; reusing existing session copy."
}

$commands = Get-Command -Module $ModuleName -CommandType Function
$permissions = [ordered]@{}

foreach ($command in $commands | Sort-Object -Property Name | Select-Object -Unique) {
    $help = Get-Help -Name $command.Name -ErrorAction SilentlyContinue
    if ($help) {
        $role = Get-HelpProperty -HelpObject $help -PropertyName 'Role'
        $functionality = Get-HelpProperty -HelpObject $help -PropertyName 'Functionality'
        $description = Get-HelpDescription -HelpObject $help
    } else {
        $role = ''
        $functionality = ''
        $description = ''
    }

    if ($role -and $functionality) {
        $permissions[$command.Name] = @{
            Role          = $role
            Functionality = $functionality
            Description   = $description
        }
    } else {
        Write-Host "Skipping $($command.Name): no Role or Functionality metadata found."
    }
}

$permissionsCaseInsensitive = [System.Collections.Hashtable]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($key in $permissions.Keys) {
    $permissionsCaseInsensitive[$key] = $permissions[$key]
}
$permissionsJson = $permissionsCaseInsensitive | ConvertTo-Json -Depth 5 -Compress
Set-Content -Path $OutputPath -Value $permissionsJson -Encoding UTF8

Write-Host "Wrote permissions JSON cache for $($permissions.Count) functions to $OutputPath"

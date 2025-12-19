param(
    [string]$ModulePath = (Join-Path $PSScriptRoot '..' 'Modules' 'CIPPCore'),
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

# Resolve defaults
if (-not (Test-Path -Path $ModulePath)) {
    throw "ModulePath '$ModulePath' not found. Provide -ModulePath to the module root."
}
$ModulePath = (Resolve-Path -Path $ModulePath).ProviderPath
if (-not $ModuleName) { $ModuleName = (Split-Path -Path $ModulePath -Leaf) }
if (-not $OutputPath) {
    $defaultLibData = Join-Path $ModulePath 'lib' 'data' 'function-permissions.json'
    $OutputPath = if (Test-Path (Split-Path -Parent $defaultLibData)) { $defaultLibData } else { Join-Path $ModulePath 'function-permissions.json' }
}

# Ensure destination directory exists
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force

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
    } else {
        $role = ''
        $functionality = ''
    }

    if ($role -and $functionality) {
        $permissions[$command.Name] = @{
            Role          = $role
            Functionality = $functionality
        }
    } else {
        Write-Host "Skipping $($command.Name): no Role or Functionality metadata found."
    }
}

# Depth 3 is sufficient for the flat hashtable of functions -> (Role, Functionality)
$json = $permissions | ConvertTo-Json -Depth 3
Set-Content -Path $OutputPath -Value $json -Encoding UTF8

Write-Host "Wrote permissions for $($permissions.Count) functions to $OutputPath"

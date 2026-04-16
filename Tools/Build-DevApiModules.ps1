$ErrorActionPreference = 'Stop'

$toolsRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $toolsRoot
$modulesRoot = Join-Path $repoRoot 'Modules'
$outputRoot = Join-Path $repoRoot 'Output'

if (-not (Get-Module -ListAvailable -Name ModuleBuilder)) {
    Install-Module -Name ModuleBuilder -Scope CurrentUser -Force
}
Import-Module -Name ModuleBuilder -Force

Write-Host "Repo root: $repoRoot"
Set-Location -Path $repoRoot

& (Join-Path $toolsRoot 'Build-FunctionParameters.ps1')
& (Join-Path $toolsRoot 'Build-FunctionPermissions.ps1')

Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPCore')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPDB')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPTests')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPStandards')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPAlerts')
Build-Module -SourcePath (Join-Path $modulesRoot 'CippExtensions')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPActivityTriggers')
Build-Module -SourcePath (Join-Path $modulesRoot 'CIPPHTTP')

$moduleNames = @(
    'CIPPCore',
    'CIPPDB',
    'CIPPTests',
    'CIPPStandards',
    'CIPPAlerts',
    'CippExtensions',
    'CIPPActivityTriggers',
    'CIPPHTTP'
)

foreach ($moduleName in $moduleNames) {
    $loadedModules = Get-Module -Name $moduleName -All
    foreach ($loadedModule in $loadedModules) {
        Remove-Module -ModuleInfo $loadedModule -Force -ErrorAction SilentlyContinue
        Write-Host "Unloaded module '$moduleName'"
    }
}

foreach ($moduleName in $moduleNames) {
    $sourceDir = Join-Path $outputRoot $moduleName
    $targetDir = Join-Path $modulesRoot $moduleName
    $renamedTargetDir = $null

    if (-not (Test-Path -Path $sourceDir)) {
        throw "Expected output module path not found: $sourceDir"
    }

    if (Test-Path -Path $targetDir) {
        $renamedTargetDir = "$targetDir.to-delete.$([guid]::NewGuid().ToString('N'))"
        Rename-Item -Path $targetDir -NewName (Split-Path -Leaf $renamedTargetDir) -Force
        Write-Host "Renamed existing module '$moduleName' to '$renamedTargetDir'"
    }

    Move-Item -Path $sourceDir -Destination $targetDir -Force
    Write-Host "Replaced module '$moduleName' from '$sourceDir'"

    if ($renamedTargetDir -and (Test-Path -Path $renamedTargetDir)) {
        Remove-Item -Path $renamedTargetDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed old module folder '$renamedTargetDir'"
    }
}

Write-Host 'Build and module replacement complete.'

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

function Get-HelpParameterMap {
    param(
        [Parameter(Mandatory = $false)]$HelpObject
    )

    $map = @{}
    if (-not $HelpObject) { return $map }

    $helpParameters = ($HelpObject | Select-Object -ExpandProperty parameters -ErrorAction SilentlyContinue).parameter
    if (-not $helpParameters) { return $map }

    foreach ($helpParam in $helpParameters) {
        $paramName = $helpParam.name
        if (-not $paramName) { continue }

        $description = @($helpParam.description.Text) -join ' '
        $map[$paramName] = ($description ?? '').Trim()
    }

    return $map
}

if (-not (Test-Path -Path $ModulePath)) {
    throw "ModulePath '$ModulePath' not found. Provide -ModulePath to the module root."
}

$ModulePath = (Resolve-Path -Path $ModulePath).ProviderPath
if (-not $ModuleName) { $ModuleName = (Split-Path -Path $ModulePath -Leaf) }
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot '..' 'Config' 'function-parameters.json'
}

$null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force

$moduleImportPath = Resolve-ModuleImportPath -Root $ModulePath -Name $ModuleName
$normalizedImportPath = [System.IO.Path]::GetFullPath($moduleImportPath)
$loaded = Get-Module -Name $ModuleName | Where-Object { [System.IO.Path]::GetFullPath($_.Path) -eq $normalizedImportPath }
if (-not $loaded) {
    Write-Host "Importing module '$ModuleName' from '$moduleImportPath'"
    Import-Module -Name $moduleImportPath -Force -ErrorAction Stop
} else {
    Write-Host "Module '$ModuleName' already loaded from '$moduleImportPath'; reusing existing session copy."
}

$commonParameters = @(
    'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable',
    'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable',
    'TenantFilter', 'APIName', 'Headers', 'ProgressAction', 'WhatIf', 'Confirm', 'NoAuthCheck'
)
$commands = Get-Command -Module $ModuleName -CommandType Function
$functionParameters = [ordered]@{}

foreach ($command in $commands | Sort-Object -Property Name | Select-Object -Unique) {
    try {
        $help = Get-Help -Name $command.Name -ErrorAction SilentlyContinue
        if (-not $help) {
            Write-Host "No help for $($command.Name); using command metadata fallback."
        }

        $helpParamMap = Get-HelpParameterMap -HelpObject $help

        $parameterList = [System.Collections.Generic.List[object]]::new()
        if ($command.Parameters) {
            foreach ($key in @($command.Parameters.Keys)) {
                if ($commonParameters -contains $key) { continue }

                $param = $command.Parameters[$key]
                $required = @($param.Attributes | Where-Object { $_.PSObject.Properties['Mandatory'] -and $_.Mandatory }).Count -gt 0

                $parameterList.Add([ordered]@{
                        Name        = $key
                        Type        = $param.ParameterType.FullName
                        Description = $helpParamMap[$key]
                        Required    = $required
                    })
            }
        }

        $functionParameters[$command.Name] = [ordered]@{
            Functionality = (($help.Functionality ?? '') + '').Trim()
            Synopsis      = (($help.Synopsis ?? '') + '').Trim()
            Parameters    = @($parameterList)
        }
    } catch {
        Write-Host "Failed to build metadata for $($command.Name): $($_.Exception.Message). Writing fallback entry."
        $functionParameters[$command.Name] = [ordered]@{
            Functionality = ''
            Synopsis      = ''
            Parameters    = @()
        }
    }
}

$json = $functionParameters | ConvertTo-Json -Depth 8 -Compress
Set-Content -Path $OutputPath -Value $json -Encoding UTF8

Write-Host "Wrote parameter metadata for $($functionParameters.Count) functions to $OutputPath"

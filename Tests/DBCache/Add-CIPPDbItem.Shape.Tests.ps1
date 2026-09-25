# Pester tests for the collection shape the cache writer records on the '<Type>-Count' row: the
# fields its rows carry, one nested level deep, with their types - what the report builder's data
# picker offers.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Add-CIPPDbItem.ps1' | Select-Object -First 1 -ExpandProperty FullName)

    $script:Written = @{}
    $script:Existing = $null
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) foreach ($e in @($Entity)) { $script:Written[$e.RowKey] = $e } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) $script:Existing }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @() }

    function Get-Shape { (ConvertFrom-Json -InputObject $script:Written['Devices-Count'].Shape).fields | ForEach-Object { "$($_.name):$($_.type)" } }
}

Describe 'Add-CIPPDbItem shape' {
    BeforeEach { $script:Written = @{}; $script:Existing = $null }

    It 'records each field with its type, one nested level deep, on the count row' {
        @(
            [PSCustomObject]@{ id = 'a'; deviceName = 'PC1'; isCompliant = $true; storage = 512; enrolledAt = '2026-09-01T10:00:00Z'; hardware = [PSCustomObject]@{ model = 'X1'; ram = 16 }; apps = @([PSCustomObject]@{ name = 'Edge' }) }
            [PSCustomObject]@{ id = 'b'; deviceName = 'PC2'; isCompliant = $false; storage = $null; lastSeen = $null }
        ) | Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Devices' -AddCount

        $Shape = @(Get-Shape)
        $Shape | Should -Contain 'deviceName:string'
        $Shape | Should -Contain 'isCompliant:boolean'
        $Shape | Should -Contain 'storage:number'
        $Shape | Should -Contain 'enrolledAt:date'
        $Shape | Should -Contain 'hardware:object'
        $Shape | Should -Contain 'hardware.model:string'
        $Shape | Should -Contain 'apps:array'
        $Shape | Should -Contain 'apps.name:string'
        $Shape | Should -Contain 'lastSeen:null'
        $script:Written['Devices-Count'].DataCount | Should -Be 2
    }

    It 'keeps the recorded shape when a count-only call follows the rows' {
        $script:Existing = @{ DataCount = 7; Shape = '{"fields":[{"name":"deviceName","type":"string"}]}' }
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Devices' -InputObject 7 -Count

        @(Get-Shape) | Should -Be @('deviceName:string')
    }

    It 'merges into the recorded shape when appending' {
        $script:Existing = @{ DataCount = 1; Shape = '{"fields":[{"name":"deviceName","type":"string"}]}' }
        @([PSCustomObject]@{ id = 'c'; osVersion = '10.0' }) | Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Devices' -AddCount -Append

        $Shape = @(Get-Shape)
        $Shape | Should -Contain 'deviceName:string'
        $Shape | Should -Contain 'osVersion:string'
        $script:Written['Devices-Count'].DataCount | Should -Be 2
    }
}

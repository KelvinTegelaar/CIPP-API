# Pester tests for Invoke-ExecSetPackageTag.
# The endpoint rebuilds the row from a fixed column list and replaces it, so any column it does not
# name is lost. Losing ManualImport would flip a manual catalog import back to "synced", and losing
# SourcePath breaks the catalog's match for a renamed template.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Test-CippTemplateWriteAccess { param($Permission, $PartitionKey, $RowKey) $true }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecSetPackageTag.ps1')

    function Invoke-Tag($Body) {
        Invoke-ExecSetPackageTag -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecSetPackageTag' }
                Headers = @{}
                Body    = [pscustomobject]$Body
            })
    }
}

Describe 'Invoke-ExecSetPackageTag keeps the repo link columns' {
    BeforeEach {
        $script:Written = $null
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{
                PartitionKey = 'IntuneTemplate'
                RowKey       = 'guid-1'
                JSON         = '{"Displayname":"OIB policy"}'
                SHA          = 'sha-1'
                Source       = 'Org/repo'
                SourcePath   = 'IntuneTemplate/OIB_policy.json'
                ManualImport = $true
            }
        }
    }

    It 'when <Action> a package tag' -ForEach @(
        @{ Action = 'adding'; Body = @{ GUID = 'guid-1'; Package = 'Pack' } }
        @{ Action = 'removing'; Body = @{ GUID = 'guid-1'; Remove = $true } }
    ) {
        (Invoke-Tag $Body).StatusCode | Should -Be 200
        $script:Written.ManualImport | Should -BeTrue
        $script:Written.SourcePath | Should -Be 'IntuneTemplate/OIB_policy.json'
        $script:Written.SHA | Should -Be 'sha-1'
        $script:Written.Source | Should -Be 'Org/repo'
    }
}

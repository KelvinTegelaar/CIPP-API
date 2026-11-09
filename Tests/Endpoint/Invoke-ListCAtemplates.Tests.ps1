# Pester tests for Invoke-ListCAtemplates: the id filter must accept every GUID the list itself publishes.
# The stock templates in backend/Config are stored with RowKey and GUID '<guid>.CATemplate.json', which the
# edit page sends back as ?GUID=<that value>.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Conditional/Invoke-ListCAtemplates.ps1'
    if (-not (Test-Path -LiteralPath $FunctionPath)) { throw "Could not locate $FunctionPath" }

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # An in-memory templates table that applies the OData filter the endpoint sends, so the tests assert on
    # what the endpoint returns and not on the text of its filter.
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity {
        param($Context, $Filter, $Property)
        foreach ($Row in $script:Rows) {
            $Condition = [regex]::Replace($Filter, "(\w+) eq '((?:[^']|'')*)'", {
                    param($Match)
                    if ("$($Row.($Match.Groups[1].Value))" -ceq ($Match.Groups[2].Value -replace "''", "'")) { '$true' } else { '$false' }
                })
            if (& ([scriptblock]::Create(($Condition -replace '\band\b', '-and' -replace '\bor\b', '-or')))) { $Row }
        }
    }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $script:Rows.Add([pscustomobject]$Entity) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . $FunctionPath

    $script:OriginalRootPath = $env:CIPPRootPath
    $script:StockId = '49a8069e-3b46-4680-a035-9250bc675446.CATemplate.json'
    $script:CustomId = '7d1f6c52-0a43-4a8e-9a39-3f5f1b6e8c11'

    function Invoke-List {
        param($Query)
        $Response = Invoke-ListCAtemplates -Request ([pscustomobject]@{ Query = [pscustomobject]$Query })
        [pscustomobject]@{ StatusCode = [int]$Response.StatusCode; Templates = @($Response.Body | ConvertFrom-Json) }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRootPath
}

Describe 'Invoke-ListCAtemplates id filter' {
    BeforeEach {
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        # The first list imports backend/Config/*.CATemplate.json once; these rows start out already imported.
        $script:Rows.Add([pscustomobject]@{ PartitionKey = 'settings'; RowKey = 'CATemplate'; CATemplate = $true })
        $script:Rows.Add([pscustomobject]@{ PartitionKey = 'CATemplate'; RowKey = $script:StockId; GUID = $script:StockId; JSON = '{"displayName":"Stock template"}' })
        $script:Rows.Add([pscustomobject]@{ PartitionKey = 'CATemplate'; RowKey = $script:CustomId; GUID = $script:CustomId; JSON = '{"displayName":"Custom template"}' })
    }

    It 'returns a stock template when asked for it by the <Parameter> the list publishes' -ForEach @(
        @{ Parameter = 'id' }
        @{ Parameter = 'GUID' }
    ) {
        $Result = Invoke-List @{ $Parameter = $script:StockId }

        $Result.StatusCode | Should -Be 200
        $Result.Templates.Count | Should -Be 1
        $Result.Templates[0].displayName | Should -Be 'Stock template'
        $Result.Templates[0].GUID | Should -Be $script:StockId
    }

    It 'returns a template created in the UI by its bare GUID' {
        $Result = Invoke-List @{ GUID = $script:CustomId }

        $Result.StatusCode | Should -Be 200
        $Result.Templates.Count | Should -Be 1
        $Result.Templates[0].displayName | Should -Be 'Custom template'
    }

    It 'returns an empty list for the unknown id <Id>' -ForEach @(
        @{ Id = '00000000-0000-4000-8000-000000000000' }
        @{ Id = '00000000-0000-4000-8000-000000000000.CATemplate.json' }
    ) {
        $Result = Invoke-List @{ GUID = $Id }

        $Result.StatusCode | Should -Be 200
        $Result.Templates.Count | Should -Be 0
    }

    It 'keeps an id with a quote inside its filter value' {
        $Result = Invoke-List @{ GUID = "x' or PartitionKey eq 'CATemplate" }

        $Result.StatusCode | Should -Be 200
        $Result.Templates.Count | Should -Be 0
    }

    It 'lists every template, sorted by name, when no id is given' {
        $Result = Invoke-List @{}

        $Result.StatusCode | Should -Be 200
        $Result.Templates.displayName | Should -Be @('Custom template', 'Stock template')
    }

    It 'accepts every GUID the first list publishes for the imported stock templates' {
        $Config = Join-Path $TestDrive 'Config'
        $null = New-Item -ItemType Directory -Path $Config
        Set-Content -LiteralPath (Join-Path $Config $script:StockId) -Value '{"displayName":"Imported stock template"}'
        $env:CIPPRootPath = $TestDrive
        $script:Rows.Clear()

        $Listed = Invoke-List @{}
        $Listed.Templates.Count | Should -Be 1
        $Listed.Templates[0].GUID | Should -Be $script:StockId

        $Result = Invoke-List @{ GUID = $Listed.Templates[0].GUID }

        $Result.StatusCode | Should -Be 200
        $Result.Templates.Count | Should -Be 1
        $Result.Templates[0].displayName | Should -Be 'Imported stock template'
    }
}

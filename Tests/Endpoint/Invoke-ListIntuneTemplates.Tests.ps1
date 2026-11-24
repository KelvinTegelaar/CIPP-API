# Pester tests for Invoke-ListIntuneTemplates' isSynced flag.
# A template imported once from the catalog keeps its repo SHA (the catalog needs it for its
# Imported / Update available badges) but nothing keeps it in sync, so it must not be listed as
# synced - that flag hides the Edit action.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    # Only the templates table has rows, matched on the partition the endpoint asks for
    function Get-CIPPAzDataTableEntity {
        param($Context, $Filter)
        if ($Context -ne 'templates' -or $Filter -notmatch "PartitionKey eq '(\w+)'") { return }
        $script:Rows | Where-Object { $_.PartitionKey -eq $Matches[1] }
    }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListIntuneTemplates.ps1')

    function New-Row($Name, $Extra, $RawJson = '{"name":"x"}') {
        $Row = @{
            PartitionKey = 'IntuneTemplate'
            RowKey       = $Name
            Package      = 'Pack'
            JSON         = (@{ Displayname = $Name; Description = 'd'; Type = 'Catalog'; RAWJson = $RawJson } | ConvertTo-Json -Compress)
        }
        foreach ($Key in $Extra.Keys) { $Row[$Key] = $Extra[$Key] }
        [pscustomobject]$Row
    }

    function Invoke-List($Query) {
        $Response = Invoke-ListIntuneTemplates -Request ([pscustomobject]@{ Query = [pscustomobject]$Query })
        @($Response.Body | ConvertFrom-Json -Depth 20)
    }
}

Describe 'Invoke-ListIntuneTemplates isSynced' {
    BeforeEach {
        $script:Rows = @(
            [pscustomobject]@{ PartitionKey = 'settings'; RowKey = 'IntuneTemplate'; IntuneTemplate = $true }
            New-Row 'Synced' @{ SHA = 'sha-1'; Source = 'Org/repo' }
            New-Row 'Manual' @{ SHA = 'sha-2'; Source = 'Org/repo'; ManualImport = $true }
            New-Row 'Local' @{}
        )
    }

    It 'lists <Name> with isSynced <Expected> in the table view' -ForEach @(
        @{ Name = 'Synced'; Expected = $true }
        @{ Name = 'Manual'; Expected = $false }
        @{ Name = 'Local'; Expected = $false }
    ) {
        $Template = Invoke-List @{ View = $true } | Where-Object displayName -EQ $Name
        $Template.isSynced | Should -Be $Expected
    }

    It 'keeps the source on a manual import, so the catalog link is still shown' {
        (Invoke-List @{ View = $true } | Where-Object displayName -EQ 'Manual').source | Should -Be 'Org/repo'
    }

    It 'applies the same rule to a row that fails to parse' {
        $script:Rows += New-Row 'Broken' @{ SHA = 'sha-3'; ManualImport = $true } 'not json'
        $Template = Invoke-List @{ View = $true } | Where-Object displayName -Like 'Broken*'
        $Template.corrupt | Should -BeTrue
        $Template.isSynced | Should -BeFalse
    }

    It 'applies the same rule to the templates listed under a package tag' {
        $Templates = (Invoke-List @{ mode = 'Tag' })[0].templates
        ($Templates | Where-Object displayName -EQ 'Synced').isSynced | Should -BeTrue
        ($Templates | Where-Object displayName -EQ 'Manual').isSynced | Should -BeFalse
    }
}

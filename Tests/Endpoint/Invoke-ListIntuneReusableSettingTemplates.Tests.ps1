# Pester tests for Invoke-ListIntuneReusableSettingTemplates
# Validates sorting, parsing, filtering, and sync flags

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListIntuneReusableSettingTemplates.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) $script:lastFilter = $Filter; return $script:tableRows }

    . $FunctionPath
}

Describe 'Invoke-ListIntuneReusableSettingTemplates' {
    BeforeEach {
        $script:lastFilter = $null
        $script:tableRows = @(
            [pscustomobject]@{
                RowKey      = 'b-guid'
                JSON        = '{"DisplayName":"B","RawJSON":"{\"b\":1}","Description":"B desc"}'
                Source      = 'sync'
                SHA         = 'abc123'
            },
            [pscustomobject]@{
                RowKey      = 'a-guid'
                RawJSON     = '{"displayName":"A"}'
                DisplayName = 'A'
                Description = 'Entity desc'
            }
        )
    }

    It 'returns sorted templates with parsed metadata and sync flag' {
        $request = [pscustomobject]@{ query = @{} }

        $response = Invoke-ListIntuneReusableSettingTemplates -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -HaveCount 2
        $response.Body[0].displayName | Should -Be 'A'
        $response.Body[0].description | Should -Be 'Entity desc'
        $response.Body[0].GUID | Should -Be 'a-guid'
        $response.Body[0].RawJSON | Should -Match '"displayName":"A"'
        $response.Body[0].isSynced | Should -BeFalse

        $response.Body[1].displayName | Should -Be 'B'
        $response.Body[1].description | Should -Be 'B desc'
        $response.Body[1].GUID | Should -Be 'b-guid'
        $response.Body[1].isSynced | Should -BeTrue
        $lastFilter | Should -Be "PartitionKey eq 'IntuneReusableSettingTemplate'"
    }

    It 'filters by ID when provided' {
        $request = [pscustomobject]@{ query = @{ ID = 'b-guid' } }

        $response = Invoke-ListIntuneReusableSettingTemplates -Request $request -TriggerMetadata $null

        $response.Body | Should -HaveCount 1
        $response.Body[0].GUID | Should -Be 'b-guid'
    }
}

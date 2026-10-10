# A corrupt template row auto-repaired on read is rewritten with only JSON/RowKey/PartitionKey/GUID.
# A row imported from a repo carries SHA and Source, which the repo sync uses to skip files that
# have not changed - dropping them on repair makes the next sync treat the row as new.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-listStandardTemplates.ps1'
    $HashFunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Get-CIPPTemplateContentHash.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) @{ Context = 'stub' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Repair-CippStandardsTemplate { param($Json, $Reference) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
    function Get-CIPPTemplateSourceUrl { param($Source, $SourcePath, $Repos) if ($Source) { "https://github.com/$Source" } }

    . $HashFunctionPath
    . $FunctionPath

    function New-Request {
        [pscustomobject]@{ Query = @{}; Headers = @{} }
    }
}

Describe 'Invoke-listStandardTemplates repair path' {
    BeforeEach {
        $script:Written = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written = $Entity }
        # Malformed JSON that fails ConvertFrom-Json outright, forcing the repair branch.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{
                    RowKey       = 'guid-1'
                    PartitionKey = 'StandardsTemplateV2'
                    GUID         = 'guid-1'
                    SHA          = 'abc123'
                    Source       = 'Org/repo'
                    JSON         = '{templateName:Bad, this is not valid json'
                }
            )
        }
        Mock -CommandName Repair-CippStandardsTemplate -MockWith { '{"templateName":"Bad"}' }
    }

    It 'carries SHA and Source across on the repaired write' {
        $null = Invoke-listStandardTemplates -Request (New-Request) -TriggerMetadata $null
        $script:Written.SHA | Should -Be 'abc123'
        $script:Written.Source | Should -Be 'Org/repo'
    }

    It 'exposes sourceUrl next to source/isSynced' {
        $Response = Invoke-listStandardTemplates -Request (New-Request) -TriggerMetadata $null
        $Template = $Response.Body | Where-Object { $_.GUID -eq 'guid-1' }
        $Template.source | Should -Be 'Org/repo'
        $Template.isSynced | Should -BeTrue
        $Template.sourceUrl | Should -Be 'https://github.com/Org/repo'
    }

    It 'writes no SHA or Source when the row being repaired never carried them' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{
                    RowKey       = 'guid-2'
                    PartitionKey = 'StandardsTemplateV2'
                    GUID         = 'guid-2'
                    JSON         = '{templateName:Bad, this is not valid json'
                }
            )
        }
        $null = Invoke-listStandardTemplates -Request (New-Request) -TriggerMetadata $null
        $script:Written.ContainsKey('SHA') | Should -BeFalse
        $script:Written.ContainsKey('Source') | Should -BeFalse
    }

    It 'carries ContentHash across on the repaired write when the row had one' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{
                    RowKey       = 'guid-3'
                    PartitionKey = 'StandardsTemplateV2'
                    GUID         = 'guid-3'
                    SHA          = 'abc123'
                    Source       = 'Org/repo'
                    ContentHash  = 'deadbeef'
                    JSON         = '{templateName:Bad, this is not valid json'
                }
            )
        }
        $null = Invoke-listStandardTemplates -Request (New-Request) -TriggerMetadata $null
        $script:Written.ContentHash | Should -Be 'deadbeef'
    }
}

Describe 'Invoke-listStandardTemplates hasLocalChanges' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
    }

    It 'is $true when the row has a Source and ContentHash that no longer match the content' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{
                    RowKey       = 'guid-4'
                    PartitionKey = 'StandardsTemplateV2'
                    GUID         = 'guid-4'
                    Source       = 'Org/repo'
                    ContentHash  = 'stale-hash'
                    JSON         = '{"templateName":"Edited locally"}'
                }
            )
        }
        $Response = Invoke-listStandardTemplates -Request (New-Request) -TriggerMetadata $null
        ($Response.Body | Where-Object { $_.GUID -eq 'guid-4' }).hasLocalChanges | Should -BeTrue
    }

    It 'is $false when the current content hash matches the stamped ContentHash' {
        $JSON = '{"templateName":"Unedited"}'
        $MatchingHash = Get-CIPPTemplateContentHash -JSON $JSON
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{
                    RowKey       = 'guid-5'
                    PartitionKey = 'StandardsTemplateV2'
                    GUID         = 'guid-5'
                    Source       = 'Org/repo'
                    ContentHash  = $MatchingHash
                    JSON         = $JSON
                }
            )
        }
        $Response = Invoke-listStandardTemplates -Request (New-Request) -TriggerMetadata $null
        ($Response.Body | Where-Object { $_.GUID -eq 'guid-5' }).hasLocalChanges | Should -BeFalse
    }

    It 'is $null when there is no Source or ContentHash (legacy synced row)' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{
                    RowKey       = 'guid-6'
                    PartitionKey = 'StandardsTemplateV2'
                    GUID         = 'guid-6'
                    JSON         = '{"templateName":"Never synced"}'
                }
            )
        }
        $Response = Invoke-listStandardTemplates -Request (New-Request) -TriggerMetadata $null
        ($Response.Body | Where-Object { $_.GUID -eq 'guid-6' }).hasLocalChanges | Should -BeNullOrEmpty
    }
}

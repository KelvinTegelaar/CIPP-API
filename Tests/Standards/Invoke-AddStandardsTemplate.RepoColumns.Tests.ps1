# A standards template imported from a template repo carries SHA and Source. The save endpoint
# replaces the row, so it must carry those columns across or the next repo sync treats the row as
# new and overwrites the edits made in CIPP with the repo copy.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-AddStandardsTemplate.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-Request {
        param($Guid)
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tester@example.com"}'))
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddStandardsTemplate' }
            Headers = @{ 'x-ms-client-principal' = $Principal; 'x-ms-original-url' = 'https://cipp.example.com/api/AddStandardsTemplate' }
            Body    = [pscustomobject]@{
                GUID         = $Guid
                templateName = 'Repo template'
                tenantFilter = @([pscustomobject]@{ value = 'AllTenants'; type = 'Tenant' })
                standards    = [pscustomobject]@{ AuditLog = [pscustomobject]@{ remediate = $true } }
            }
        }
    }
}

Describe 'Invoke-AddStandardsTemplate repo columns' {
    BeforeEach {
        $script:Written = $null
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Add-AzDataTableEntity -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written = $Entity }
    }

    It 'carries SHA and Source across when the existing row was imported from a repo' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ RowKey = 'guid-1'; PartitionKey = 'StandardsTemplateV2'; SHA = 'abc123'; Source = 'Org/repo'; JSON = '{}' }
        }
        $null = Invoke-AddStandardsTemplate -Request (New-Request -Guid 'guid-1')
        $script:Written.SHA | Should -Be 'abc123'
        $script:Written.Source | Should -Be 'Org/repo'
        ($script:Written.JSON | ConvertFrom-Json).templateName | Should -Be 'Repo template'
    }

    It 'writes no SHA or Source for a template that was never imported' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        $null = Invoke-AddStandardsTemplate -Request (New-Request -Guid 'guid-2')
        $script:Written.ContainsKey('SHA') | Should -BeFalse
        $script:Written.ContainsKey('Source') | Should -BeFalse
    }

    It 'also carries SourcePath and ContentHash across when the existing row has them' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{
                RowKey       = 'guid-3'
                PartitionKey = 'StandardsTemplateV2'
                SHA          = 'abc123'
                Source       = 'Org/repo'
                SourcePath   = 'StandardsTemplateV2/Repo_template.json'
                ContentHash  = 'deadbeef'
                JSON         = '{}'
            }
        }
        $null = Invoke-AddStandardsTemplate -Request (New-Request -Guid 'guid-3')
        $script:Written.SourcePath | Should -Be 'StandardsTemplateV2/Repo_template.json'
        $script:Written.ContentHash | Should -Be 'deadbeef'
    }

    It 'writes no SourcePath or ContentHash for a template that was never imported' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        $null = Invoke-AddStandardsTemplate -Request (New-Request -Guid 'guid-4')
        $script:Written.ContainsKey('SourcePath') | Should -BeFalse
        $script:Written.ContainsKey('ContentHash') | Should -BeFalse
    }
}

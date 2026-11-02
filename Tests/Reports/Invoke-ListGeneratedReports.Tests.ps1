# ListGeneratedReports lists reports from a projected read (no Blocks), skips raw split part rows, and keeps AllTenants
# to managed tenants. A single report by GUID still returns its content.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter 'Invoke-ListGeneratedReports.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Message } }
    function Write-LogMessage { param($user, $API, $message, $Sev, $LogData) }

    . $FunctionPath

    function Invoke-List ([hashtable]$Query) {
        $Response = Invoke-ListGeneratedReports -Request ([pscustomobject]@{ Query = $Query; Headers = @{} }) -TriggerMetadata @{ FunctionName = 'ListGeneratedReports' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body | ConvertFrom-Json)
    }
}

Describe 'Invoke-ListGeneratedReports' {
    BeforeEach {
        $script:Properties = $null
        Mock Get-CIPPTable { @{ Context = 'stub' } }
        Mock Get-CIPPAzDataTableEntity {
            $script:Properties = $Property
            @(
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'a'; TemplateName = 'CIS'; TenantFilter = 'contoso.com'; GeneratedAt = '2026-10-01'; Status = 'Completed'; Blocks = '[{"type":"test"}]' }
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'a-part1' }
                [pscustomobject]@{ PartitionKey = 'removed.com'; RowKey = 'b'; TemplateName = 'CIS'; TenantFilter = 'removed.com'; GeneratedAt = '2026-10-01'; Status = 'Completed' }
            )
        }
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'Contoso.com' } }
    }

    It 'lists from a projected read without content and skips split part rows' {
        $Reports = Invoke-List @{ tenantFilter = 'contoso.com' }
        $script:Properties | Should -Not -Contain 'Blocks'
        $script:Properties | Should -Contain 'RowKey'
        $Reports.RowKey | Should -Be @('a', 'b')
        $Reports[0].PSObject.Properties.Name | Should -Not -Contain 'Blocks'
    }

    It 'keeps all-tenant results to managed tenants, ignoring domain case' {
        $Reports = Invoke-List @{ tenantFilter = 'AllTenants' }
        $Reports.RowKey | Should -Be @('a')
    }

    It 'returns the content of a single report' {
        $Reports = Invoke-List @{ ReportGUID = '11111111-1111-1111-1111-111111111111' }
        $script:Properties | Should -BeNullOrEmpty
        $Reports[0].Sections | Should -Be 1
        $Reports[0].Blocks[0].type | Should -Be 'test'
    }
}

# Pester tests for Invoke-ExecGetReportBuilderPdf
#
# The endpoint is AnyTenant (the request carries only the report id), so it scopes the stored PDF
# row by its tenant partition itself: unrestricted callers get any report, restricted callers only
# the reports of tenants they can access, and a 404 otherwise.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecGetReportBuilderPdf.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecGetReportBuilderPdf.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
        [object]$ContentType
        [object]$Headers
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $TableName, $Filter, $Property) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Write-LogMessage { param($Headers, $API, $message, $Sev, $tenant, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    $script:ReportId = '11111111-2222-3333-4444-555555555555'
    function New-PdfRequest {
        [pscustomobject]@{
            Headers = @{}
            Query   = [pscustomobject]@{ id = $script:ReportId }
            Body    = $null
        }
    }
}

Describe 'Invoke-ExecGetReportBuilderPdf' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ TableName = 'ReportBuilderPdfs' } }
        Mock -CommandName ConvertTo-CIPPODataFilterValue -MockWith { $Value }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{
                PartitionKey = 'contoso.onmicrosoft.com'
                RowKey       = $script:ReportId
                FileName     = 'Report.pdf'
                Pdf          = [Convert]::ToBase64String([byte[]](37, 80, 68, 70))
            }
        }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = 'contoso-id'; defaultDomainName = 'contoso.onmicrosoft.com' }
            [pscustomobject]@{ customerId = 'fabrikam-id'; defaultDomainName = 'fabrikam.onmicrosoft.com' }
        }
    }

    It 'returns the PDF to an unrestricted caller' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        $Response = Invoke-ExecGetReportBuilderPdf -Request (New-PdfRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Response.ContentType | Should -Be 'application/pdf'
        $Response.Body | Should -Be ([byte[]](37, 80, 68, 70))
    }

    It "returns the PDF to a restricted caller who can access the report's tenant" {
        Mock -CommandName Test-CIPPAccess -MockWith { @('contoso-id') }
        $Response = Invoke-ExecGetReportBuilderPdf -Request (New-PdfRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
    }

    It "hides the report from a restricted caller who cannot access its tenant" {
        Mock -CommandName Test-CIPPAccess -MockWith { @('fabrikam-id') }
        $Response = Invoke-ExecGetReportBuilderPdf -Request (New-PdfRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
        $Response.Body | Should -Not -BeOfType [byte[]]
    }

    It 'hides the report from a caller with no tenants at all' {
        Mock -CommandName Test-CIPPAccess -MockWith { @() }
        $Response = Invoke-ExecGetReportBuilderPdf -Request (New-PdfRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
    }
}

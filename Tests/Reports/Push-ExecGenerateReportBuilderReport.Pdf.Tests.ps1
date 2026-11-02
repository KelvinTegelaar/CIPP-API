# Pester tests for the PDF path of Push-ExecGenerateReportBuilderReport: a rendered PDF is stored in
# its own table (never on the report row the list reads), attached to the scheduled-email envelope,
# and -PreviewOnly returns bytes without storing anything.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    function Find-Module1([string]$Name) {
        Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    . (Find-Module1 'ConvertTo-CippReportPdf.ps1')
    . (Find-Module1 'Get-CippReportTenantName.ps1')
    . (Find-Module1 'Resolve-CippReportDataToken.ps1')
    . (Find-Module1 'Push-ExecGenerateReportBuilderReport.ps1')

    # Static stubs for the storage/data helpers the generator calls. The Add stub captures the stored
    # entity per table so the test can assert on where the PDF went. No pass-through mocks.
    $script:Stored = @{}
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) @() }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $script:Stored[$Context] = $Entity }
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { param($Id, [switch]$SkipImageData) @() }
    function Get-Tenants { param($TenantFilter) @{ displayName = 'Contoso' } }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) @() }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Write-LogMessage { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception)" } }

    $script:Blocks = ConvertTo-Json -InputObject @(@{ type = 'blank'; title = 'Summary'; content = '<p>Hello</p>' }) -Depth 10
}

Describe 'Push-ExecGenerateReportBuilderReport PDF path' {
    It 'stores the base64 PDF in the ReportBuilderPdfs table, keyed by the report GUID, not on the report row' {
        $script:Stored = @{}
        $null = Push-ExecGenerateReportBuilderReport -TenantFilter 'contoso.onmicrosoft.com' -TemplateName 'Test Report' -Blocks $script:Blocks
        $Report = $script:Stored['ReportBuilderReports']
        $Pdf = $script:Stored['ReportBuilderPdfs']
        $Report | Should -Not -BeNullOrEmpty
        $Report.Pdf | Should -BeNullOrEmpty
        $Pdf.RowKey | Should -Be $Report.RowKey
        $Pdf.PartitionKey | Should -Be 'contoso.onmicrosoft.com'
        $Pdf.FileName | Should -Be 'Test_Report_contoso_onmicrosoft_com.pdf'
        # The stored value must be valid base64 of a real PDF.
        $bytes = [Convert]::FromBase64String($Pdf.Pdf)
        [System.Text.Encoding]::ASCII.GetString($bytes[0..4]) | Should -Be '%PDF-'
    }

    It 'returns the rendered PDF as an application/pdf task attachment' {
        $result = Push-ExecGenerateReportBuilderReport -TenantFilter 'contoso.onmicrosoft.com' -TemplateName 'Test Report' -Blocks $script:Blocks
        $result.TaskAttachments | Should -Not -BeNullOrEmpty
        @($result.TaskAttachments | Where-Object { $_.ContentType -eq 'application/pdf' }).Count | Should -Be 1
    }

    It 'PreviewOnly returns bytes without persisting anything' {
        $script:Stored = @{}
        $result = Push-ExecGenerateReportBuilderReport -TenantFilter 'contoso.onmicrosoft.com' -Blocks $script:Blocks -PreviewOnly
        [System.Text.Encoding]::ASCII.GetString($result.PdfBytes[0..4]) | Should -Be '%PDF-'
        $script:Stored.Count | Should -Be 0
    }
}

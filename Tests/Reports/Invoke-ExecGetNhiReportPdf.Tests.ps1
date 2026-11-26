# Pester tests for the NHI report PDF endpoint: the request is validated before any work, only a completed
# run renders (anything else is a 404), and the stored run and its containment reach the report.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }
    $null = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('HttpStatusCode', [System.Net.HttpStatusCode])

    $Reporting = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Directory -Filter 'Reporting' | Select-Object -First 1
    Get-ChildItem -Path $Reporting.FullName -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    foreach ($Name in 'ConvertTo-CippReportPdf.ps1', 'Get-CippErrorStatusCode.ps1', 'Invoke-ExecGetNhiReportPdf.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name | Select-Object -First 1 -ExpandProperty FullName)
    }
    function Get-CippReportTenantName { param($TenantFilter, $BrandingPresetId) 'Contoso' }
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { @() }
    function Get-CIPPTextReplacement { param($Text) $Text }
    function Write-LogMessage {}
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, [switch]$IncludeResults, $Kind) }

    $Sample = Get-Content (Join-Path $RepoRoot 'Config/ReportSamples/nhi.json') -Raw | ConvertFrom-Json
    function Invoke-Report($Query) {
        Invoke-ExecGetNhiReportPdf -Request @{ Query = $Query; Body = @{}; Headers = @{}; Params = @{ CIPPEndpoint = 'ExecGetNhiReportPdf' } } -TriggerMetadata @{}
    }
}

Describe 'Invoke-ExecGetNhiReportPdf' {
    It 'renders a completed run as a PDF named after the app' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'NHI-1'; Status = 'Completed'; Results = $Sample.nhiData; Containment = $Sample.containment } }
        $Response = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; caseId = 'NHI-1' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.ContentType | Should -Be 'application/pdf'
        $Response.Headers.'Content-Disposition' | Should -Be 'inline; filename="NHI_Report_Sample_Invoice_Sync.pdf"'
        [System.Text.Encoding]::ASCII.GetString($Response.Body[0..4]) | Should -Be '%PDF-'
        Should -Invoke Get-CIPPBecReport -Times 1 -Exactly -ParameterFilter { $Kind -eq 'NHI' -and $CaseId -eq 'NHI-1' -and $IncludeResults }
    }

    It 'renders the C-suite summary for variant=summary, and the full report for anything else' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'NHI-1'; Status = 'Completed'; Results = $Sample.nhiData; Containment = $Sample.containment } }
        $Summary = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; caseId = 'NHI-1'; variant = 'summary' }
        $Summary.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Summary.Headers.'Content-Disposition' | Should -Be 'inline; filename="NHI_Summary_Sample_Invoice_Sync.pdf"'
        $Other = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; caseId = 'NHI-1'; variant = 'bogus' }
        $Other.Headers.'Content-Disposition' | Should -Be 'inline; filename="NHI_Report_Sample_Invoice_Sync.pdf"'
        $Summary.Body.Length | Should -BeLessThan $Other.Body.Length
    }

    It 'rejects a request without a case before reading anything' {
        Mock Get-CIPPBecReport { }
        $Response = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Get-CIPPBecReport -Times 0 -Exactly
    }

    It 'returns 404 for a run that has not completed' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'NHI-1'; Status = 'Running' } }
        $Response = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; caseId = 'NHI-1' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        $Response.Body | Should -BeLike 'No completed NHI investigation*'
    }
}

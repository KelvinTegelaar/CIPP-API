# Pester tests for the branding preview endpoint: every sample report type renders through its tree
# builder against a supplied branding, and an unknown type is a 400. This is also what keeps
# Config/ReportSamples/<type>.json in step with the builders' input shapes.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))
    $env:CIPPRootPath = $RepoRoot

    # Craft injects these types; shim them so the entrypoint's return statements bind.
    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }
    $null = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('HttpStatusCode', [System.Net.HttpStatusCode])

    $Reporting = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Directory -Filter 'Reporting' | Select-Object -First 1
    Get-ChildItem -Path $Reporting.FullName -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    foreach ($Name in 'ConvertTo-CippReportPdf.ps1', 'Invoke-ExecPreviewBrandingReportPdf.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name | Select-Object -First 1 -ExpandProperty FullName)
    }
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { param($Id, [switch]$SkipImageData) @() }
    function Write-LogMessage { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception)" } }

    function Invoke-Preview($Body) {
        Invoke-ExecPreviewBrandingReportPdf -Request @{ Body = $Body; Headers = @{} } -TriggerMetadata @{ FunctionName = 'ExecPreviewBrandingReportPdf' }
    }
}

Describe 'Invoke-ExecPreviewBrandingReportPdf' {
    It 'renders the <type> sample against the supplied branding' -ForEach @(
        @{ type = 'executive' }, @{ type = 'reportBuilder' }, @{ type = 'shadowAI' }, @{ type = 'bec' }
        @{ type = 'sharing' }, @{ type = 'permissions' }, @{ type = 'mailFlow' }, @{ type = 'licensing' }, @{ type = 'baseline' }
    ) {
        $Response = Invoke-Preview @{ reportType = $type; branding = @{ colour = '#0E4C92'; coverStock = 'none'; footerText = '%tenantname% preview' } }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.ContentType | Should -Be 'application/pdf'
        [System.Text.Encoding]::ASCII.GetString($Response.Body[0..4]) | Should -Be '%PDF-'
    }

    It 'falls back to the executive sample and the saved branding when the body is empty' {
        $Response = Invoke-Preview @{}
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        [System.Text.Encoding]::ASCII.GetString($Response.Body[0..4]) | Should -Be '%PDF-'
    }

    It 'rejects an unknown report type' {
        $Response = Invoke-Preview @{ reportType = 'nope' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body | Should -BeLike "Unknown report type 'nope'*"
    }
}

# Pester tests for the License Optimisation PDF endpoint: the request is validated before any work,
# the page's analysis settings reach Get-CIPPLicenseRecommendation exactly as ListLicenseRecommendations
# passes them, the section switches reach the tree, and the report renders to a PDF.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    # Craft injects these types; shim them so the entrypoint's return statements bind.
    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }
    $null = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('HttpStatusCode', [System.Net.HttpStatusCode])

    $Reporting = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Directory -Filter 'Reporting' | Select-Object -First 1
    Get-ChildItem -Path $Reporting.FullName -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    foreach ($Name in 'ConvertTo-CippReportPdf.ps1', 'Get-CippReportTenantName.ps1', 'Invoke-ExecGetLicenseReportPdf.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name | Select-Object -First 1 -ExpandProperty FullName)
    }
    function Get-Tenants { @{ displayName = 'Contoso Ltd'; defaultDomainName = 'contoso.onmicrosoft.com' } }
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { @() }
    # A plain function: the -TenantFilter/-EscapeForJson it is also called with land in $args.
    function Get-CIPPTextReplacement { param($Text) $Text }
    function Write-LogMessage {}
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception)" } }

    $Sample = Get-Content (Join-Path $RepoRoot 'Config/ReportSamples/licensing.json') -Raw | ConvertFrom-Json
    # Records the analysis settings it was called with and returns the preview sample in the live shape.
    function Get-CIPPLicenseRecommendation {
        param($TenantFilter, $Currency, $InactiveDays, $TenureMonths, $RecommendDowngrades, $RecommendUpgrades, $RecommendTerms, $ProtectSecurityFeatures)
        $script:Called = $PSBoundParameters
        $Sample
    }

    function Invoke-Report($Body, $Query = @{}) {
        $script:Called = $null
        Invoke-ExecGetLicenseReportPdf -Request @{ Body = $Body; Query = $Query; Headers = @{} } -TriggerMetadata @{ FunctionName = 'ExecGetLicenseReportPdf' }
    }
}

Describe 'Invoke-ExecGetLicenseReportPdf' {
    It 'renders the report as a PDF named after the tenant' {
        $Response = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.ContentType | Should -Be 'application/pdf'
        $Response.Headers.'Content-Disposition' | Should -Be 'inline; filename="Licensing_Report_contoso_onmicrosoft_com.pdf"'
        [System.Text.Encoding]::ASCII.GetString($Response.Body[0..4]) | Should -Be '%PDF-'
    }

    It 'reports on the query tenant, the one the tenant-scope check authorised, over a body tenant' {
        $null = Invoke-Report @{ tenantFilter = 'other.onmicrosoft.com' } @{ tenantFilter = 'contoso.onmicrosoft.com' }
        $Called.TenantFilter | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'passes the page analysis settings through, with only an explicit false turning a switch off' {
        $null = Invoke-Report @{
            tenantFilter = 'contoso.onmicrosoft.com'; currency = 'eur'; inactiveDays = 30; tenureMonths = '12'
            recommendDowngrades = $false; recommendUpgrades = 'off'; protectSecurityFeatures = $true
        }
        $Called.Currency | Should -Be 'EUR'
        $Called.InactiveDays | Should -Be 30
        $Called.TenureMonths | Should -Be 12
        $Called.RecommendDowngrades | Should -BeFalse
        $Called.RecommendUpgrades | Should -BeFalse
        $Called.RecommendTerms | Should -BeTrue
        $Called.ProtectSecurityFeatures | Should -BeTrue
    }

    It 'defaults every analysis setting the way ListLicenseRecommendations does' {
        $null = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com' }
        $Called.Currency | Should -Be 'USD'
        $Called.InactiveDays | Should -Be 90
        $Called.TenureMonths | Should -Be 6
        $Called.RecommendDowngrades | Should -BeTrue
    }

    It 'drops only the sections switched off' {
        Mock Build-CippLicenseReportTree { @{ Blocks = @(@{ type = 'page'; title = 'Summary' }); Variables = @{ coverlabel = 'x' } } }
        $null = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; sections = @{ spend = $false; terms = $true } }
        Should -Invoke Build-CippLicenseReportTree -Times 1 -ParameterFilter {
            $Sections.spend -eq $false -and $Sections.terms -and $Sections.reclaim -and $Sections.method -and $Data.TenantName -eq 'Contoso Ltd'
        }
    }

    It 'rejects <case> with a 400 before gathering anything' -ForEach @(
        @{ case = 'a missing tenant'; body = @{}; message = 'A single tenant*' }
        @{ case = 'AllTenants'; body = @{ tenantFilter = 'AllTenants' }; message = 'A single tenant*' }
        @{ case = 'a malformed currency'; body = @{ tenantFilter = 't'; currency = 'EURO' }; message = 'currency*' }
        @{ case = 'an out-of-range inactiveDays'; body = @{ tenantFilter = 't'; inactiveDays = 0 }; message = 'inactiveDays*' }
        @{ case = 'a non-numeric tenureMonths'; body = @{ tenantFilter = 't'; tenureMonths = 'soon' }; message = 'tenureMonths*' }
    ) {
        $Response = Invoke-Report $body
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body | Should -BeLike $message
        $Called | Should -BeNullOrEmpty
    }

    It 'returns a 500 with the error when the analysis fails' {
        Mock Get-CIPPLicenseRecommendation { throw 'cache unavailable' }
        $Response = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body | Should -BeLike '*cache unavailable*'
    }
}

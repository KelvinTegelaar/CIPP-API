# BEC PDF request branding follows the same preset-id contract as other server PDFs.
BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $null = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecGetBecReportPdf.ps1')
    function Get-CIPPBecReport {
        param($TenantFilter, $CaseId, $UserId, [switch]$IncludeResults)
        [pscustomobject]@{
            CaseId = 'BEC-1'; Status = 'Completed'; UserId = 'u1'
            DisplayName = 'User'; UserPrincipalName = 'user@contoso.com'
            Results = [pscustomobject]@{ CaseId = 'BEC-1' }
        }
    }
    function Get-CippReportTenantName { param($TenantFilter, $BrandingPresetId) 'Contoso' }
    function Build-CippBecReportTree {
        param($UserData, $BecData, $TenantName, $Variant)
        @{ Blocks = @(@{ type = 'blank' }); Variables = @{} }
    }
    function ConvertTo-CippReportPdf {
        param($Blocks, $Variables, $TenantName, $TenantFilter, $ReportName, $BrandingPresetId)
        [byte[]]@(37, 80, 68, 70, 45)
    }
    function Write-LogMessage {}
    function Get-CippException { param($Exception) @{ NormalizedError = [string]$Exception } }
    function Invoke-BecPdfTest($Variant, $PresetId) {
        Invoke-ExecGetBecReportPdf -Request @{
            Query = @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1'; variant = $Variant; brandingPresetId = $PresetId }
            Body = @{}; Headers = @{}
        } -TriggerMetadata @{ FunctionName = 'ExecGetBecReportPdf' }
    }
}
Describe 'Invoke-ExecGetBecReportPdf branding preset' {
    It 'passes the chosen full preset through to tenant naming and PDF rendering' {
        Mock Get-CippReportTenantName { 'Contoso' }
        Mock ConvertTo-CippReportPdf { [byte[]]@(37, 80, 68, 70, 45) }
        $Response = Invoke-BecPdfTest full 'p-full'
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Get-CippReportTenantName -Times 1 -ParameterFilter { $BrandingPresetId -eq 'p-full' }
        Should -Invoke ConvertTo-CippReportPdf -Times 1 -ParameterFilter { $BrandingPresetId -eq 'p-full' }
    }
    It 'passes the chosen summary preset through independently' {
        Mock ConvertTo-CippReportPdf { [byte[]]@(37, 80, 68, 70, 45) }
        $Response = Invoke-BecPdfTest summary 'p-summary'
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke ConvertTo-CippReportPdf -Times 1 -ParameterFilter { $BrandingPresetId -eq 'p-summary' }
    }
    It 'uses global branding when no preset was selected' {
        Mock ConvertTo-CippReportPdf { [byte[]]@(37, 80, 68, 70, 45) }
        $Response = Invoke-BecPdfTest full ''
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke ConvertTo-CippReportPdf -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($BrandingPresetId) }
    }
}

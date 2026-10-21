# The fixed-report PDF endpoints pass the caller's branding preset to both tenant naming and rendering.
BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

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

    foreach ($File in @(
            'Teams-Sharepoint/Invoke-ExecGetSharingReportPdf.ps1'
            'Teams-Sharepoint/Invoke-ExecGetPermissionsReportPdf.ps1'
            'Email-Exchange/Reports/Invoke-ExecGetMailFlowReportPdf.ps1'
            'Tenant/AI/Invoke-ExecGetShadowAIReportPdf.ps1'
            'Identity/Administration/Users/Invoke-ExecGetBecReportPdf.ps1'
        )) {
        . (Join-Path $RepoRoot "Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/$File")
    }

    function Get-CippReportTenantName { param($TenantFilter, $BrandingPresetId) }
    function ConvertTo-CippReportPdf { param($Blocks, $Variables, $TenantName, $TenantFilter, $ReportName, $BrandingPresetId) }
    function Get-CIPPSharePointSharingReport { param($TenantFilter) @{} }
    function Get-CIPPSharePointPermissionsReport { param($TenantFilter) @{} }
    function Get-CIPPShadowAIReport { param($TenantFilter) @{} }
    function New-ExoRequest { param($TenantId, $Cmdlet, $CmdParams) @() }
    function Get-CIPPBecReport {
        param($TenantFilter, $CaseId, $UserId, [switch]$IncludeResults)
        [pscustomobject]@{ CaseId = 'BEC-1'; Status = 'Completed'; UserId = 'u1'; Results = [pscustomobject]@{ CaseId = 'BEC-1' } }
    }
    function Build-CippSharingReportTree { param($Data) @{ Blocks = @(); Variables = @{} } }
    function Build-CippPermissionsReportTree { param($Data) @{ Blocks = @(); Variables = @{} } }
    function Build-CippMailFlowReportTree { param($Data) @{ Blocks = @(); Variables = @{} } }
    function Build-CippShadowAIReportTree { param($Data, $SectionConfig) @{ Blocks = @(); Variables = @{} } }
    function Build-CippBecReportTree { param($UserData, $BecData, $TenantName, $Variant) @{ Blocks = @(); Variables = @{} } }
    function Get-CippException { param($Exception) @{ NormalizedError = [string]$Exception } }
    function Write-LogMessage {}
}

Describe 'Report PDF branding preset' {
    BeforeEach {
        Mock Get-CippReportTenantName { 'Contoso' }
        Mock ConvertTo-CippReportPdf { [byte[]]@(37, 80, 68, 70, 45) }
    }

    It '<Endpoint> forwards brandingPresetId from the <In>' -ForEach @(
        @{ Endpoint = 'Invoke-ExecGetSharingReportPdf'; In = 'query'; Extra = @{} }
        @{ Endpoint = 'Invoke-ExecGetPermissionsReportPdf'; In = 'query'; Extra = @{} }
        @{ Endpoint = 'Invoke-ExecGetMailFlowReportPdf'; In = 'query'; Extra = @{} }
        @{ Endpoint = 'Invoke-ExecGetShadowAIReportPdf'; In = 'body'; Extra = @{ sectionConfig = @{} } }
        @{ Endpoint = 'Invoke-ExecGetBecReportPdf'; In = 'query'; Extra = @{ caseId = 'BEC-1'; variant = 'summary' } }
    ) {
        $Params = @{ tenantFilter = 'contoso.onmicrosoft.com'; brandingPresetId = 'p1' } + $Extra
        $Request = if ($In -eq 'body') { @{ Query = @{}; Body = $Params; Headers = @{} } } else { @{ Query = $Params; Body = @{}; Headers = @{} } }

        $Response = & $Endpoint -Request $Request -TriggerMetadata @{ FunctionName = $Endpoint }

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        Should -Invoke Get-CippReportTenantName -Times 1 -Exactly -ParameterFilter { $BrandingPresetId -eq 'p1' }
        Should -Invoke ConvertTo-CippReportPdf -Times 1 -Exactly -ParameterFilter { $BrandingPresetId -eq 'p1' }
    }
}

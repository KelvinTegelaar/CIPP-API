# Report endpoints must pass the report-specific branding preset through to both tenant naming and PDF rendering.
BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $null = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    foreach ($File in @(
        'Teams-Sharepoint/Invoke-ExecGetSharingReportPdf.ps1'
        'Teams-Sharepoint/Invoke-ExecGetPermissionsReportPdf.ps1'
        'Email-Exchange/Reports/Invoke-ExecGetMailFlowReportPdf.ps1'
        'Tenant/AI/Invoke-ExecGetShadowAIReportPdf.ps1'
    )) {
        . (Join-Path $RepoRoot "Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/$File")
    }

    function Get-CippReportTenantName { param($TenantFilter, $BrandingPresetId) 'Contoso' }
    function ConvertTo-CippReportPdf {
        param($Blocks, $Variables, $TenantName, $TenantFilter, $ReportName, $BrandingPresetId)
        [byte[]]@(37, 80, 68, 70, 45)
    }
    function Get-CIPPSharePointSharingReport {
        param($TenantFilter)
        @{ summary = @{}; links = @(); topRecipients = @(); topLibraries = @() }
    }
    function Get-CIPPSharePointPermissionsReport {
        param($TenantFilter)
        @{ summary = @{}; assignments = @(); skippedSites = @() }
    }
    function Get-CIPPShadowAIReport {
        param($TenantFilter)
        @{ summary = @{}; detectedApps = @(); consentedApps = @(); topTools = @(); byRisk = @() }
    }
    function Build-CippSharingReportTree { param($Data) @{ Blocks = @(@{ type = 'blank' }); Variables = @{} } }
    function Build-CippPermissionsReportTree { param($Data) @{ Blocks = @(@{ type = 'blank' }); Variables = @{} } }
    function Build-CippMailFlowReportTree { param($Data) @{ Blocks = @(@{ type = 'blank' }); Variables = @{} } }
    function Build-CippShadowAIReportTree { param($Data, $SectionConfig) @{ Blocks = @(@{ type = 'blank' }); Variables = @{} } }
    function New-ExoRequest { param($TenantId, $Cmdlet, $CmdParams) @() }
    function Get-CippException { param($Exception) @{ NormalizedError = [string]$Exception } }
    function Write-LogMessage {}
}

Describe 'Report PDF branding preset forwarding' {
    It '<Report> passes branding to the tenant label and PDF renderer' -ForEach @(
        @{ Report = 'Sharing'; Endpoint = 'Invoke-ExecGetSharingReportPdf'; Preset = 'sharing-preset'; Post = $false }
        @{ Report = 'Permissions'; Endpoint = 'Invoke-ExecGetPermissionsReportPdf'; Preset = 'permissions-preset'; Post = $false }
        @{ Report = 'Mail Flow'; Endpoint = 'Invoke-ExecGetMailFlowReportPdf'; Preset = 'mail-preset'; Post = $false }
        @{ Report = 'Shadow AI'; Endpoint = 'Invoke-ExecGetShadowAIReportPdf'; Preset = 'ai-preset'; Post = $true }
    ) {
        Mock Get-CippReportTenantName { 'Contoso' }
        Mock ConvertTo-CippReportPdf { [byte[]]@(37, 80, 68, 70, 45) }
        $Query = @{ tenantFilter = 'contoso.onmicrosoft.com' }
        $Body = @{}
        if ($Post) {
            $Body = @{ tenantFilter = 'contoso.onmicrosoft.com'; brandingPresetId = $Preset; sectionConfig = @{} }
        } else {
            $Query.brandingPresetId = $Preset
        }
        $Response = & $Endpoint -Request @{ Query = $Query; Body = $Body; Headers = @{} } -TriggerMetadata @{ FunctionName = $Endpoint }

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Get-CippReportTenantName -Times 1 -Exactly -ParameterFilter { $BrandingPresetId -eq $Preset }
        Should -Invoke ConvertTo-CippReportPdf -Times 1 -Exactly -ParameterFilter { $BrandingPresetId -eq $Preset }
    }

    It '<Report> uses global branding when no preset is selected' -ForEach @(
        @{ Report = 'Sharing'; Endpoint = 'Invoke-ExecGetSharingReportPdf' }
        @{ Report = 'Permissions'; Endpoint = 'Invoke-ExecGetPermissionsReportPdf' }
        @{ Report = 'Mail Flow'; Endpoint = 'Invoke-ExecGetMailFlowReportPdf' }
        @{ Report = 'Shadow AI'; Endpoint = 'Invoke-ExecGetShadowAIReportPdf' }
    ) {
        Mock Get-CippReportTenantName { 'Contoso' }
        Mock ConvertTo-CippReportPdf { [byte[]]@(37, 80, 68, 70, 45) }
        $Response = & $Endpoint -Request @{
            Query = @{ tenantFilter = 'contoso.onmicrosoft.com' }
            Body = @{}; Headers = @{}
        } -TriggerMetadata @{ FunctionName = $Endpoint }

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke ConvertTo-CippReportPdf -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($BrandingPresetId) }
    }
}

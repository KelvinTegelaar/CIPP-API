BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-Tenants {
        param($TenantFilter, [switch]$IncludeErrors)
        @([pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 'contoso.onmicrosoft.com' }).Where({ $null -eq $script:CippAllowedTenantsStorage.Value -or $script:CippAllowedTenantsStorage.Value -contains $_.customerId })
    }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) if ($Filter -match 'RowKey') { $script:Template } }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Select-CippAllowedTenantData.ps1')
    $UsersPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users'
    foreach ($Name in 'Invoke-RemoveJITAdminTemplate', 'Invoke-RemoveUserDefaultTemplate', 'Invoke-EditJITAdminTemplate') {
        . (Join-Path $UsersPath "$Name.ps1")
    }

    $TemplateId = '11111111-1111-1111-1111-111111111111'
    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tester@example.com"}'))
    function Invoke-Write($Endpoint) {
        $Body = [pscustomobject]@{ ID = $TemplateId; GUID = $TemplateId; tenantFilter = 'contoso.onmicrosoft.com'; templateName = 'Renamed' }
        & $Endpoint -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'Test' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Query = @{}; Body = $Body })
    }
    function Set-Template($Tenant) {
        $script:Template = [pscustomobject]@{ RowKey = $TemplateId; JSON = (@{ templateName = 'Template'; tenantFilter = $Tenant } | ConvertTo-Json) }
    }
}

Describe '<Endpoint> template tenant scope' -ForEach @(
    @{ Endpoint = 'Invoke-RemoveJITAdminTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Endpoint = 'Invoke-RemoveUserDefaultTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Endpoint = 'Invoke-EditJITAdminTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
) {
    BeforeEach {
        $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
        $script:CippAllowedTenantsStorage.Value = @('tenant-1')
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Add-CIPPAzDataTableEntity { }
    }
    AfterAll { $script:CippAllowedTenantsStorage = $null }

    It 'refuses a template for <Tenant> from a tenant-restricted caller' -ForEach @(
        @{ Tenant = 'fabrikam.onmicrosoft.com' }
        @{ Tenant = 'AllTenants' }
    ) {
        Set-Template $Tenant
        (Invoke-Write $Endpoint).StatusCode | Should -Be 403
        Should -Invoke $Writer -Times 0
    }

    It 'changes a template for a tenant the caller can access' {
        Set-Template 'contoso.onmicrosoft.com'
        (Invoke-Write $Endpoint).StatusCode | Should -Be 200
        Should -Invoke $Writer -Times 1
    }

    It 'lets an unrestricted caller change an all-tenant template' {
        $script:CippAllowedTenantsStorage.Value = $null
        Set-Template 'AllTenants'
        (Invoke-Write $Endpoint).StatusCode | Should -Be 200
        Should -Invoke $Writer -Times 1
    }
}

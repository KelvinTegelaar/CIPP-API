BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) $script:Rows }
    function Write-LogMessage { param($headers, $API, $message, $sev) }
    function Select-CippAllowedTenantData {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string[]]$TenantProperty)
        process { if ($null -eq $script:TenantAccess -or $script:TenantAccess -contains $InputObject.($TenantProperty[0])) { $InputObject } }
    }
    $UsersPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users'
    . (Join-Path $UsersPath 'Invoke-ListJITAdminTemplates.ps1')
    . (Join-Path $UsersPath 'Invoke-ListNewUserDefaults.ps1')

    function New-TemplateRow($Name, $Tenant) {
        [pscustomobject]@{ GUID = $Name; RowKey = $Name; JSON = (@{ templateName = $Name; tenantFilter = $Tenant } | ConvertTo-Json) }
    }

    function Get-TemplateNames($Endpoint, $Query) {
        $Response = & $Endpoint -Request ([pscustomobject]@{ Params = @{}; Headers = @{}; Query = $Query; Body = $null })
        @(($Response.Body | ConvertFrom-Json).templateName | Sort-Object)
    }
}

Describe '<Endpoint> tenant scope' -ForEach @(
    @{ Endpoint = 'Invoke-ListJITAdminTemplates' }
    @{ Endpoint = 'Invoke-ListNewUserDefaults' }
) {
    BeforeEach {
        $script:Rows = @(
            New-TemplateRow 'shared' 'AllTenants'
            New-TemplateRow 'mine' 'contoso.onmicrosoft.com'
            New-TemplateRow 'theirs' 'fabrikam.onmicrosoft.com'
        )
        $script:TenantAccess = @('contoso.onmicrosoft.com')
    }

    It 'lists all-tenant templates and the caller''s own tenant templates' {
        Get-TemplateNames $Endpoint @{} | Should -Be @('mine', 'shared')
        Get-TemplateNames $Endpoint @{ TenantFilter = 'contoso.onmicrosoft.com' } | Should -Be @('mine', 'shared')
    }

    It 'hides another tenant''s templates when that tenant is requested directly' {
        Get-TemplateNames $Endpoint @{ TenantFilter = 'fabrikam.onmicrosoft.com' } | Should -Be @('shared')
    }

    It 'lists every template for an unrestricted caller' {
        $script:TenantAccess = $null
        Get-TemplateNames $Endpoint @{} | Should -Be @('mine', 'shared', 'theirs')
    }
}

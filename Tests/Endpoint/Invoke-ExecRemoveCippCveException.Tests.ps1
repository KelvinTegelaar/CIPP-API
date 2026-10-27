BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) $script:Rows }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Removed.Add($Entity.RowKey) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:TenantAccess }
    function Select-CippAllowedTenantData {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string[]]$TenantProperty)
        process { if ($script:TenantAccess -contains 'AllTenants' -or $script:TenantAccess -contains $InputObject.($TenantProperty[0])) { $InputObject } }
    }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ExecRemoveCippCveException.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')

    function Invoke-Remove($Scope) {
        Invoke-ExecRemoveCippCveException -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecRemoveCippCveException' }
                Headers = @{}
                Query   = @{ tenantFilter = 'contoso.onmicrosoft.com'; cveId = 'CVE-2024-0001'; removeScope = $Scope }
            }) -TriggerMetadata @{}
    }
}

Describe 'Invoke-ExecRemoveCippCveException tenant scope' {
    BeforeEach {
        $script:Removed = [System.Collections.Generic.List[string]]::new()
        $script:TenantAccess = @('contoso.onmicrosoft.com')
        $script:Rows = @(
            [pscustomobject]@{ PartitionKey = 'CVE-2024-0001'; RowKey = 'contoso.onmicrosoft.com' }
            [pscustomobject]@{ PartitionKey = 'CVE-2024-0001'; RowKey = 'fabrikam.onmicrosoft.com' }
            [pscustomobject]@{ PartitionKey = 'CVE-2024-0001'; RowKey = 'ALL' }
        )
    }

    It 'removes AllAffected exceptions only for tenants the caller can access' {
        (Invoke-Remove 'AllAffected').StatusCode | Should -Be ([HttpStatusCode]::OK)
        @($script:Removed) | Should -Be @('contoso.onmicrosoft.com')
    }

    It 'refuses to remove the Global exception for a tenant-restricted caller' {
        (Invoke-Remove 'Global').StatusCode | Should -Be ([HttpStatusCode]::Forbidden)
        $script:Removed.Count | Should -Be 0
    }

    It 'lets an all-tenant caller remove <Scope>' -ForEach @(
        @{ Scope = 'AllAffected'; Expected = @('contoso.onmicrosoft.com', 'fabrikam.onmicrosoft.com') }
        @{ Scope = 'Global'; Expected = @('ALL') }
    ) {
        $script:TenantAccess = @('AllTenants')
        (Invoke-Remove $Scope).StatusCode | Should -Be ([HttpStatusCode]::OK)
        @($script:Removed) | Should -Be $Expected
    }
}

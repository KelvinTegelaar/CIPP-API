BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename, $Table) @{ TableName = $tablename ?? $Table } }
    function Get-CIPPAzDataTableEntity {
        param($TableName, $Filter, $Property)
        if ($TableName -eq 'Config') { return @{ PartitionKey = 'Domains'; RowKey = 'Domains'; Resolver = 'Google' } }
        $script:DomainFilter = $Filter
        $script:DomainRows
    }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Saved = $Entity }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Removed = $Entity }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:TenantAccess }
    function Select-CippAllowedTenantData {
        param([Parameter(ValueFromPipeline)]$InputObject, $TenantProperty)
        process { if ($InputObject.TenantGUID -in $script:TenantAccess) { $InputObject } }
    }
    function Write-LogMessage { param($API, $tenant, $headers, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecDnsConfig.ps1')

    function Invoke-Dns($Body) {
        Invoke-ExecDnsConfig -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecDnsConfig' }; Headers = @{}; Query = @{}; Body = [pscustomobject]$Body })
    }
}

Describe 'Invoke-ExecDnsConfig domain scope' {
    BeforeEach {
        $script:Removed = $null
        $script:Saved = $null
        $script:TenantAccess = @('tenant-a')
    }

    It 'escapes the domain in the RemoveDomain filter' {
        $script:DomainRows = @()
        Invoke-Dns @{ Action = 'RemoveDomain'; Domain = "x' or RowKey ne '" } | Out-Null
        $script:DomainFilter | Should -Be "RowKey eq 'x'' or RowKey ne '''"
    }

    It '<Action> refuses when any row for the domain belongs to another tenant' -ForEach @(
        @{ Action = 'RemoveDomain' }
        @{ Action = 'SetDkimConfig' }
    ) {
        $script:DomainRows = @(
            [pscustomobject]@{ RowKey = 'contoso.com'; TenantGUID = 'tenant-a'; DkimSelectors = '' }
            [pscustomobject]@{ RowKey = 'contoso.com'; TenantGUID = 'tenant-b'; DkimSelectors = '' }
        )
        $Response = Invoke-Dns @{ Action = $Action; Domain = 'contoso.com'; Selector = 'selector1' }
        $Response.StatusCode | Should -Be 403
        $script:Removed | Should -BeNullOrEmpty
        $script:Saved | Should -BeNullOrEmpty
    }

    It 'removes a domain whose rows are all in scope' {
        $script:DomainRows = @([pscustomobject]@{ RowKey = 'contoso.com'; TenantGUID = 'tenant-a' })
        $Response = Invoke-Dns @{ Action = 'RemoveDomain'; Domain = 'contoso.com' }
        $Response.StatusCode | Should -Be 200
        $script:Removed.RowKey | Should -Be 'contoso.com'
    }

    It 'lets an unrestricted caller remove any domain' {
        $script:TenantAccess = @('AllTenants')
        $script:DomainRows = @([pscustomobject]@{ RowKey = 'contoso.com'; TenantGUID = 'tenant-b' })
        (Invoke-Dns @{ Action = 'RemoveDomain'; Domain = 'contoso.com' }).StatusCode | Should -Be 200
    }
}

# A tenantGroup request is an All Tenants read narrowed to the caller's tenants in that group.

BeforeAll {
    if (-not ('Microsoft.Azure.Functions.PowerShellWorker.HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'namespace Microsoft.Azure.Functions.PowerShellWorker { public class HttpResponseContext { public object StatusCode { get; set; } public object Body { get; set; } } }'
    }

    $CoreRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules/CIPPCore/Public'
    $null = New-Module -Name TenantGroupCore -ArgumentList $CoreRoot -ScriptBlock {
        param($Root)
        function Initialize-CippRequestContext {}
        function Set-CippUserAgentContext { param($Headers) }
        function Get-CIPPFeatureFlag { $script:TestFlags }
        $script:TestFlags = @()
        function Set-TestFlags { param($Value) $script:TestFlags = $Value }
        function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
        function Measure-CippTask { param($TaskName, $Metadata, $Script) & $Script }
        function Test-CIPPAccess {
            param($Request, [switch]$TenantList, [switch]$GroupList)
            if ($TenantList) { return $script:TestAllowedTenants }
            if ($GroupList) { return 'AllGroups' }
            if ($Request.Params.CIPPEndpoint -eq 'ExecWrite') { throw [System.ArgumentException]::new('view only') }
            $true
        }
        function Get-TestScope { $script:CippAllowedTenantsStorage.Value }
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = $null }
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = $null }
        . (Join-Path $Root 'Entrypoints/HTTP Functions/New-CippCoreRequest.ps1')
        . (Join-Path $Root 'Get-CippErrorStatusCode.ps1')
        $script:TestAllowedTenants = @('AllTenants')
        function Set-TestAllowedTenants { param($Value) $script:TestAllowedTenants = $Value }
        Export-ModuleMember -Function New-CippCoreRequest, Get-TestScope, Set-TestAllowedTenants, Set-TestFlags
    }
    $null = New-Module -Name TenantGroupHttp -ScriptBlock {
        function Invoke-ListThing {
            param($Request, $TriggerMetadata)
            $Response = [pscustomobject]@{ StatusCode = 200; Body = @{ tenantFilter = $Request.Query.tenantFilter; tenantGroup = $Request.Query.tenantGroup; scope = (Get-TestScope) } }
            $Response.PSObject.TypeNames.Insert(0, 'Microsoft.Azure.Functions.PowerShellWorker.HttpResponseContext')
            $Response
        }
        function Invoke-ExecWrite { param($Request, $TriggerMetadata) }
        Export-ModuleMember -Function Invoke-*
    }

    function Send-Request($Endpoint, $Query, $Body = $null) {
        New-CippCoreRequest -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = $Endpoint }; Headers = @{}; Query = $Query; Body = $Body }) -TriggerMetadata @{}
    }
}

AfterAll {
    Remove-Module TenantGroupCore, TenantGroupHttp -Force -ErrorAction SilentlyContinue
}

Describe 'New-CippCoreRequest tenant groups' {
    # Test-CIPPAccess -TenantList returns the group-narrowed list (covered in its own tests); the router stores it
    It 'runs tenantGroup on its own as All Tenants with the access check''s narrowed list as scope (<Shape>)' -ForEach @(
        @{ Shape = 'hashtable query'; Query = @{ tenantGroup = 'g1' } }
        @{ Shape = 'object query'; Query = [pscustomobject]@{ tenantGroup = 'g1' } }
    ) {
        Set-TestAllowedTenants @('t1', 't2')
        $Response = Send-Request 'ListThing' $Query
        [int]$Response.StatusCode | Should -Be 200
        $Response.Body.tenantFilter | Should -Be 'AllTenants'
        $Response.Body.scope | Should -Be @('t1', 't2')
    }
    It 'refuses a request that names both a tenant and a group (<Filter>)' -ForEach @(
        @{ Filter = 'AllTenants' }
        @{ Filter = 'contoso.com' }
    ) {
        $Response = Send-Request 'ListThing' @{ tenantFilter = $Filter; tenantGroup = 'g1' }
        [int]$Response.StatusCode | Should -Be 400
    }

    It 'reads tenantGroup from a POST body the same as from the query' {
        Set-TestAllowedTenants @('t1')
        $Response = Send-Request 'ListThing' @{} ([pscustomobject]@{ tenantGroup = 'g1'; Name = 'x' })
        [int]$Response.StatusCode | Should -Be 200
        $Response.Body.tenantFilter | Should -Be 'AllTenants'
        $Response.Body.tenantGroup | Should -Be 'g1'
        $Response.Body.scope | Should -Be @('t1')
    }

    It 'refuses a body that names both a tenant and a group' {
        $Response = Send-Request 'ListThing' @{} ([pscustomobject]@{ tenantGroup = 'g1'; tenantFilter = 'contoso.com' })
        [int]$Response.StatusCode | Should -Be 400
    }

    It 'refuses a group selection sent as tenantFilter (<Shape>)' -ForEach @(
        @{ Shape = 'query'; Query = @{ tenantFilter = 'group:g1' }; Body = $null }
        @{ Shape = 'body string'; Query = @{}; Body = [pscustomobject]@{ tenantFilter = 'group:g1' } }
        @{ Shape = 'body label/value'; Query = @{}; Body = [pscustomobject]@{ tenantFilter = [pscustomobject]@{ value = 'group:g1'; label = 'G' } } }
    ) {
        $Response = Send-Request 'ListThing' $Query $Body
        [int]$Response.StatusCode | Should -Be 400
        $Response.Body | Should -Be 'Send a tenant group as tenantGroup, not tenantFilter.'
    }

    It 'refuses a tenantGroup while the TenantGroupSelector feature flag is off' {
        Set-TestFlags @([pscustomobject]@{ Id = 'TenantGroupSelector'; Enabled = $false; Endpoints = @() })
        try {
            $Response = Send-Request 'ListThing' @{ tenantGroup = 'g1' }
            [int]$Response.StatusCode | Should -Be 400
            $Response.Body | Should -BeLike 'Tenant group selection is turned off*'
        } finally { Set-TestFlags @() }
    }

    It 'still accepts tenant groups picked in a form (selectedTenants) while the feature flag is off' {
        Set-TestFlags @([pscustomobject]@{ Id = 'TenantGroupSelector'; Enabled = $false; Endpoints = @() })
        try {
            $Body = [pscustomobject]@{ selectedTenants = @([pscustomobject]@{ type = 'Group'; value = 'g1'; label = 'G' }) }
            $Response = Send-Request 'ListThing' @{} $Body
            [int]$Response.StatusCode | Should -Be 200
        } finally { Set-TestFlags @() }
    }

    It 'leaves the scope alone without a group' {
        Set-TestAllowedTenants @('AllTenants')
        $Response = Send-Request 'ListThing' @{ tenantFilter = 'AllTenants' }
        $Response.Body.scope | Should -BeNullOrEmpty
    }

    It 'returns 400 when the access check refuses the request as invalid input' {
        $Response = Send-Request 'ExecWrite' @{ tenantGroup = 'g1' }
        [int]$Response.StatusCode | Should -Be 400
        $Response.Body | Should -Be 'view only'
    }
}

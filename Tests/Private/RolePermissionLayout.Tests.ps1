# Pins how built-in roles (Config/cipp-roles.json) and custom roles combine, on both sides of access:
#   - Get-CippAllowedPermissions: what /api/me shows and what the MCP tool catalog is filtered by
#   - Test-CIPPAccess: what a request is actually allowed to do
# The two are separate implementations of the same rules, so every combination is also checked for
# parity: a permission is listed exactly when a request needing it is allowed. A change to the role
# layout, or to either implementation alone, fails here.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AuthDir = Join-Path $BackendRoot 'Modules/CIPPCore/Public/Authentication'
    $PrivateAuthDir = Join-Path $BackendRoot 'Modules/CIPPCore/Private/Authentication'

    function Get-CippApiClient { param($AppId) }
    function Test-IpInRange { param($IPAddress, $Range) $false }
    function Get-CippAccessScopeRule { param($Role) }
    function Get-CIPPRoleIPRanges { param($Roles) @('Any') }
    function Test-CIPPAccessUserRole { param($User) $User }
    function Resolve-CippImpersonation { param($User, $Request) [pscustomobject]@{ User = $User; Impersonating = $null; RealRoles = $User.userRoles } }
    function Expand-CIPPTenantGroups { param($TenantFilter) @() }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $user, $LogData) }

    . (Join-Path $AuthDir 'Test-CIPPAccess.ps1')
    . (Join-Path $AuthDir 'Test-CippRoleTenantScope.ps1')
    . (Join-Path $AuthDir 'Get-CippAllowedPermissions.ps1')
    . (Join-Path $PrivateAuthDir 'Get-CippRequestIPAddress.ps1')
    . (Join-Path $PrivateAuthDir 'Find-CippBaseRole.ps1')

    # The real built-in role layout, for both implementations.
    $script:OriginalRootPath = $env:CIPPRootPath
    $env:CIPPRootPath = $BackendRoot
    $script:CIPPBaseRoles = [System.IO.File]::ReadAllText((Join-Path $BackendRoot 'Config/cipp-roles.json')) | ConvertFrom-Json

    # A permission universe covering every built-in include/exclude rule, plus a Read-only object.
    $script:Universe = @(
        'CIPP.Core.Read', 'CIPP.Core.ReadWrite'
        'CIPP.AppSettings.Read', 'CIPP.AppSettings.ReadWrite'
        'CIPP.Admin.Read', 'CIPP.Admin.ReadWrite'
        'CIPP.SuperAdmin.Read', 'CIPP.SuperAdmin.ReadWrite'
        'Identity.User.Read', 'Identity.User.ReadWrite'
        'Exchange.Mailbox.Read', 'Exchange.Mailbox.ReadWrite'
        'Tenant.Standards.Read', 'Tenant.Standards.ReadWrite'
        'Endpoint.Device.Read'
    )
    function Get-CippHttpPermissions { $script:Universe }

    # One endpoint per permission: Probe_Identity_User_Read needs Identity.User.Read, and so on.
    function Get-ProbeEndpoint([string]$Permission) { 'Probe_' + ($Permission -replace '\.', '_') }
    $script:CIPPFunctionPermissions = @{}
    foreach ($Permission in $script:Universe) {
        $script:CIPPFunctionPermissions["Invoke-$(Get-ProbeEndpoint $Permission)"] = @{ Role = $Permission; Functionality = 'Entrypoint' }
    }

    $script:T1 = [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 't1.example.com' }
    $script:T2 = [pscustomobject]@{ customerId = 'tenant-2'; defaultDomainName = 't2.example.com' }
    $script:T3 = [pscustomobject]@{ customerId = 'tenant-3'; defaultDomainName = 't3.example.com' }
    function Get-Tenants { param([switch]$IncludeErrors) @($script:T1, $script:T2, $script:T3) }

    # Custom roles as Get-CIPPRolePermissions returns them (ReadWrite already expanded to its Read).
    $script:CustomRoles = @{
        'identity-rw'   = @{ Permissions = @('CIPP.Core.Read', 'Identity.User.Read', 'Identity.User.ReadWrite') }
        'exchange-read' = @{ Permissions = @('CIPP.Core.Read', 'Exchange.Mailbox.Read') }
        'standards-rw'  = @{ Permissions = @('Tenant.Standards.Read', 'Tenant.Standards.ReadWrite') }
        't1-blocks'     = @{ Permissions = @('Identity.User.Read'); AllowedTenants = @('tenant-1'); BlockedEndpoints = @('Probe_Identity_User_Read') }
        't2-allows'     = @{ Permissions = @('Identity.User.Read'); AllowedTenants = @('tenant-2') }
    }
    function Get-CIPPRolePermissions {
        param([string]$RoleName)
        $Def = $script:CustomRoles[$RoleName]
        if (-not $Def) { throw "Role $RoleName not found." }
        [pscustomobject]@{
            Role             = $RoleName
            Permissions      = @($Def.Permissions)
            AllowedTenants   = @($Def.AllowedTenants ?? @('AllTenants'))
            BlockedTenants   = @()
            BlockedEndpoints = @($Def.BlockedEndpoints ?? @())
        }
    }

    function New-UserRequest([string[]]$Roles, [string]$Permission, [string]$Tenant = 't1.example.com') {
        $Principal = @{ identityProvider = 'aad'; userId = 'u1'; userDetails = 'user@contoso.com'; userRoles = @($Roles) } | ConvertTo-Json -Compress
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = (Get-ProbeEndpoint $Permission) }
            Headers = @{ 'x-ms-client-principal' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Principal)); 'x-forwarded-for' = '1.2.3.4' }
            Query   = @{ tenantFilter = $Tenant }
            Body    = @{}
        }
    }

    function New-ApiClientRequest([string]$Permission, [string]$Tenant = 't1.example.com') {
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = (Get-ProbeEndpoint $Permission) }
            Headers = @{ 'x-ms-client-principal-idp' = 'aad'; 'x-ms-client-principal-name' = '11111111-1111-1111-1111-111111111111'; 'x-forwarded-for' = '1.2.3.4' }
            Query   = @{ tenantFilter = $Tenant }
            Body    = @{}
        }
    }

    function Test-Allowed($Request) {
        try { [bool](Test-CIPPAccess -Request $Request) } catch { $false }
    }

    function Get-DeniedReason($Request) {
        try { $null = Test-CIPPAccess -Request $Request; 'allowed' } catch { $_.Exception.Message }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRootPath
}

Describe 'Role permission layout' {
    It 'lists <Name>' -ForEach @(
        @{ Name = 'readonly'; Roles = @('readonly'); Expected = @('CIPP.Core.Read', 'Endpoint.Device.Read', 'Exchange.Mailbox.Read', 'Identity.User.Read', 'Tenant.Standards.Read') }
        @{ Name = 'editor'; Roles = @('editor'); Expected = @('CIPP.Core.Read', 'CIPP.Core.ReadWrite', 'Endpoint.Device.Read', 'Exchange.Mailbox.Read', 'Exchange.Mailbox.ReadWrite', 'Identity.User.Read', 'Identity.User.ReadWrite', 'Tenant.Standards.Read') }
        @{ Name = 'admin'; Roles = @('admin'); Expected = @('CIPP.Admin.Read', 'CIPP.Admin.ReadWrite', 'CIPP.AppSettings.Read', 'CIPP.AppSettings.ReadWrite', 'CIPP.Core.Read', 'CIPP.Core.ReadWrite', 'Endpoint.Device.Read', 'Exchange.Mailbox.Read', 'Exchange.Mailbox.ReadWrite', 'Identity.User.Read', 'Identity.User.ReadWrite', 'Tenant.Standards.Read', 'Tenant.Standards.ReadWrite') }
        @{ Name = 'superadmin'; Roles = @('superadmin'); Expected = 'everything' }
        @{ Name = 'one custom role'; Roles = @('identity-rw'); Expected = @('CIPP.Core.Read', 'Identity.User.Read', 'Identity.User.ReadWrite') }
        @{ Name = 'two custom roles as their union'; Roles = @('identity-rw', 'exchange-read'); Expected = @('CIPP.Core.Read', 'Exchange.Mailbox.Read', 'Identity.User.Read', 'Identity.User.ReadWrite') }
        @{ Name = 'readonly narrowed by a custom role, which cannot lift it to ReadWrite'; Roles = @('readonly', 'identity-rw'); Expected = @('CIPP.Core.Read', 'Identity.User.Read') }
        @{ Name = 'editor narrowed by a custom role'; Roles = @('editor', 'identity-rw'); Expected = @('CIPP.Core.Read', 'Identity.User.Read', 'Identity.User.ReadWrite') }
        @{ Name = 'editor narrowed by a custom role, keeping the editor exclusion'; Roles = @('editor', 'standards-rw'); Expected = @('Tenant.Standards.Read') }
        @{ Name = 'admin, which a custom role does not narrow'; Roles = @('admin', 'exchange-read'); Expected = @('CIPP.Admin.Read', 'CIPP.Admin.ReadWrite', 'CIPP.AppSettings.Read', 'CIPP.AppSettings.ReadWrite', 'CIPP.Core.Read', 'CIPP.Core.ReadWrite', 'Endpoint.Device.Read', 'Exchange.Mailbox.Read', 'Exchange.Mailbox.ReadWrite', 'Identity.User.Read', 'Identity.User.ReadWrite', 'Tenant.Standards.Read', 'Tenant.Standards.ReadWrite') }
    ) {
        $Want = if ($Expected -eq 'everything') { $script:Universe } else { $Expected }
        @(Get-CippAllowedPermissions -UserRoles $Roles -InformationAction SilentlyContinue) | Should -Be @($Want | Sort-Object)
    }
}

Describe 'Listed permissions match what a request is allowed to do' {
    It 'for a user holding <Label>' -ForEach @(
        @{ Label = 'readonly'; Roles = @('readonly') }
        @{ Label = 'editor'; Roles = @('editor') }
        @{ Label = 'admin'; Roles = @('admin') }
        @{ Label = 'superadmin'; Roles = @('superadmin') }
        @{ Label = 'one custom role'; Roles = @('identity-rw') }
        @{ Label = 'two custom roles'; Roles = @('identity-rw', 'exchange-read') }
        @{ Label = 'readonly + custom'; Roles = @('readonly', 'identity-rw') }
        @{ Label = 'editor + custom'; Roles = @('editor', 'identity-rw') }
        @{ Label = 'editor + custom touching an editor exclusion'; Roles = @('editor', 'standards-rw') }
        @{ Label = 'admin + custom'; Roles = @('admin', 'exchange-read') }
    ) {
        $Listed = @(Get-CippAllowedPermissions -UserRoles $Roles -InformationAction SilentlyContinue)
        $Mismatches = foreach ($Permission in $script:Universe) {
            $Allowed = Test-Allowed (New-UserRequest -Roles $Roles -Permission $Permission)
            if ($Allowed -ne ($Listed -contains $Permission)) { "$Permission listed=$($Listed -contains $Permission) allowed=$Allowed" }
        }
        $Mismatches | Should -BeNullOrEmpty
    }

    It 'for an API client whose role is <Role>' -ForEach @(
        @{ Role = 'readonly' }
        @{ Role = 'editor' }
        @{ Role = 'identity-rw' }
    ) {
        Mock Get-CippApiClient { [pscustomobject]@{ AppName = 'Probe'; Role = $Role; IPRange = @('Any') } }
        $Listed = @(Get-CippAllowedPermissions -UserRoles @($Role) -InformationAction SilentlyContinue)
        $Mismatches = foreach ($Permission in $script:Universe) {
            $Allowed = Test-Allowed (New-ApiClientRequest -Permission $Permission)
            if ($Allowed -ne ($Listed -contains $Permission)) { "$Permission listed=$($Listed -contains $Permission) allowed=$Allowed" }
        }
        $Mismatches | Should -BeNullOrEmpty
    }
}

Describe 'Tenant-scoped custom roles mixed with a built-in role' {
    # Role t1-blocks grants Identity.User.Read on tenant 1 but blocks the endpoint; t2-allows grants it
    # on tenant 2. The permission is listed whenever some role grants it; tenants and blocks are only
    # decided per request.
    It '<Roles> on <Tenant>: <Expected>' -ForEach @(
        @{ Roles = @('editor', 't1-blocks', 't2-allows'); Tenant = 't1.example.com'; Expected = 'blocked' }
        @{ Roles = @('editor', 't1-blocks', 't2-allows'); Tenant = 't2.example.com'; Expected = 'allowed' }
        @{ Roles = @('editor', 't1-blocks', 't2-allows'); Tenant = 't3.example.com'; Expected = 'tenant not allowed' }
        @{ Roles = @('readonly', 't1-blocks', 't2-allows'); Tenant = 't1.example.com'; Expected = 'blocked' }
        @{ Roles = @('readonly', 't1-blocks', 't2-allows'); Tenant = 't2.example.com'; Expected = 'allowed' }
        @{ Roles = @('readonly', 't1-blocks'); Tenant = 't1.example.com'; Expected = 'blocked' }
        @{ Roles = @('readonly', 't1-blocks'); Tenant = 't2.example.com'; Expected = 'tenant not allowed' }
        @{ Roles = @('t1-blocks', 't2-allows'); Tenant = 't2.example.com'; Expected = 'allowed' }
        @{ Roles = @('admin', 't1-blocks'); Tenant = 't1.example.com'; Expected = 'allowed' }
    ) {
        $Reason = Get-DeniedReason (New-UserRequest -Roles $Roles -Permission 'Identity.User.Read' -Tenant $Tenant)
        switch ($Expected) {
            'allowed' { $Reason | Should -Be 'allowed' }
            'blocked' { $Reason | Should -BeLike "*custom role 't1-blocks' has blocked this endpoint*" }
            'tenant not allowed' { $Reason | Should -Be 'Access to this tenant is not allowed' }
        }
    }

    It 'lists the permission for <Roles> regardless of tenant' -ForEach @(
        @{ Roles = @('editor', 't1-blocks', 't2-allows') }
        @{ Roles = @('readonly', 't1-blocks') }
    ) {
        @(Get-CippAllowedPermissions -UserRoles $Roles -InformationAction SilentlyContinue) | Should -Be @('Identity.User.Read')
    }
}

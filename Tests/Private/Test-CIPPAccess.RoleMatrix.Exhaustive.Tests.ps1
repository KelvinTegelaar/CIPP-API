# Every combination of up to two custom roles, built from every permission level x tenant scope x endpoint
# block, alone and alongside each built-in role, in both role orders. Each answer is compared with a
# reference model of the rules below, written independently of Test-CIPPAccess:
#  - admin/superadmin ignore custom roles; readonly/editor cap the permission, custom roles set the tenants
#  - a tenant is allowed only by a role that itself grants the endpoint's permission (no cross-role mixing)
#  - every tenant the request names must be allowed; a granting role that blocks the endpoint denies
#    wherever it reaches; a role with no allowed tenants reaches none
#  - the tenant/group list for a request comes only from roles granting the endpoint, minus blocks

BeforeDiscovery {
    $Scopes = @('empty', 't1', 't2', 'all', 'allbut2', 'g12', 'g3', 't1g3', 'stale', 't1self', 'g12no2', 'allbutg12')
    $Archetypes = @(foreach ($Perm in @('none', 'read', 'write')) { foreach ($Scope in $Scopes) { foreach ($Block in @('open', 'block')) { "$Perm-$Scope-$Block" } } })
    function Get-Pair($First, $Second) { , @($First, $(if ($Second -eq $First) { "$Second~2" } else { $Second })) }

    # The full matrix (every pair of every role, with every built-in role: ~1M checks, ~20 min) only runs
    # with CIPP_ROLE_MATRIX_FULL=1, never in CI or a routine local run. By default every role is checked
    # alone (and beside readonly/editor), and every pair from a core set covering each permission, scope
    # shape and block.
    # The standards endpoint only differs from the user-write endpoint where a built-in role excludes it.
    $AllOps = @('Write', 'Read', 'Standards')
    $script:Rows = if ($env:CIPP_ROLE_MATRIX_FULL -eq '1') {
        foreach ($Base in @('', 'readonly', 'editor', 'admin', 'superadmin')) {
            for ($i = 0; $i -lt $Archetypes.Count; $i++) {
                @{ Name = "$Base + $($Archetypes[$i]) + every other role, in both orders"; Base = $Base; Ops = $AllOps; Sets = @(, @($Archetypes[$i])) + @(foreach ($Partner in $Archetypes[$i..($Archetypes.Count - 1)]) { Get-Pair $Archetypes[$i] $Partner }) }
            }
        }
    } else {
        $Core = @('write-t1-open', 'read-t2-open', 'read-all-open', 'write-all-open', 'write-allbut2-open', 'write-g12-open', 'read-g3-open', 'write-t1-block', 'write-all-block', 'write-g12no2-open', 'write-empty-open', 'none-t1-open')
        @{ Name = 'each role alone'; Base = ''; Ops = @('Write', 'Read'); Sets = @(foreach ($Role in $Archetypes) { , @($Role) }) }
        foreach ($Base in @('readonly', 'editor')) {
            @{ Name = "$Base + each role alone"; Base = $Base; Ops = $AllOps; Sets = @(foreach ($Role in $Archetypes) { , @($Role) }) }
        }
        # admin and superadmin ignore custom roles, so the core roles are enough to show it.
        foreach ($Base in @('admin', 'superadmin')) {
            @{ Name = "$Base + each core role"; Base = $Base; Ops = $AllOps; Sets = @(foreach ($Role in $Core) { , @($Role) }) }
        }
        @{ Name = 'every pair of core roles, in both orders'; Base = ''; Ops = @('Write', 'Read'); Sets = @(for ($i = 0; $i -lt $Core.Count; $i++) { foreach ($Partner in $Core[$i..($Core.Count - 1)]) { Get-Pair $Core[$i] $Partner } }) }
    }
    # Set CIPP_ROLE_MATRIX_FILTER to a row name pattern (e.g. '*write-t1-*') to run a slice while iterating.
    if ($env:CIPP_ROLE_MATRIX_FILTER) { $script:Rows = @($script:Rows | Where-Object { $_.Name -like $env:CIPP_ROLE_MATRIX_FILTER }) }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication'
    $PrivateAuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Private/Authentication'

    class HttpResponseContext { [int]$StatusCode; [object]$Body; [object]$ContentType }

    # Plain stubs rather than Mocks: this file makes close to a million access checks.
    function Get-CippApiClient { param($AppId) }
    function Test-IpInRange { param($IPAddress, $Range) $false }
    function Get-CIPPRoleIPRanges { param($Roles) @('Any') }
    function Test-CIPPAccessUserRole { param($User) $User }
    function Resolve-CippImpersonation { param($User, $Request) [pscustomobject]@{ User = $User; Impersonating = $null; RealRoles = $User.userRoles } }
    function Get-CippAllowedPermissions { param($UserRoles) @() }
    function Get-CippAccessScopeVersion { 'v1' }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $user, $LogData) }
    function Get-Tenants { param([switch]$IncludeErrors) $script:Tenants }
    function Get-CIPPRolePermissions {
        param($Role)
        if (-not $script:RoleDefs.ContainsKey($Role)) { throw "Role $Role not found." }
        $script:RoleDefs[$Role]
    }
    function Expand-CIPPTenantGroups {
        param($TenantFilter)
        foreach ($Id in $script:GroupMembers["$(@($TenantFilter)[0].value)"]) { [pscustomobject]@{ addedFields = [pscustomobject]@{ customerId = $Id } } }
    }

    . (Join-Path $AuthDir 'Test-CippRoleTenantScope.ps1')
    . (Join-Path $AuthDir 'Test-CIPPAccess.ps1')
    . (Join-Path $AuthDir 'Get-CippAccessScopeRule.ps1')
    . (Join-Path $AuthDir 'Expand-CippScopeTenantItem.ps1')
    . (Join-Path $PrivateAuthDir 'Find-CippBaseRole.ps1')
    . (Join-Path $PrivateAuthDir 'Get-CippRequestIPAddress.ps1')
    . (Join-Path $PrivateAuthDir 'New-CippMeResponse.ps1')

    $script:CIPPBaseRoles = [pscustomobject]@{
        readonly   = [pscustomobject]@{ include = @('*.Read'); exclude = @('CIPP.SuperAdmin.*', 'CIPP.Admin.*', 'CIPP.AppSettings.*') }
        editor     = [pscustomobject]@{ include = @('*.Read', '*.ReadWrite'); exclude = @('CIPP.SuperAdmin.*', 'CIPP.Admin.*', 'CIPP.AppSettings.*', 'Tenant.Standards.ReadWrite') }
        admin      = [pscustomobject]@{ include = @('*'); exclude = @('CIPP.SuperAdmin.*') }
        superadmin = [pscustomobject]@{ include = @('*'); exclude = @() }
    }
    $script:CIPPFunctionPermissions = @{
        'Invoke-ExecResetPass'     = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' }
        'Invoke-ListUsers'         = @{ Role = 'Identity.User.Read'; Functionality = 'Entrypoint' }
        'Invoke-ExecStandardThing' = @{ Role = 'Tenant.Standards.ReadWrite'; Functionality = 'Entrypoint' }
    }
    $script:Ops = [ordered]@{
        Write     = @{ Endpoint = 'ExecResetPass'; Permission = 'Identity.User.ReadWrite' }
        Read      = @{ Endpoint = 'ListUsers'; Permission = 'Identity.User.Read' }
        Standards = @{ Endpoint = 'ExecStandardThing'; Permission = 'Tenant.Standards.ReadWrite' }
    }
    # Blocking archetypes block the user endpoints; the standards endpoint stays open to show a block is per endpoint.
    $script:BlockedEndpoints = @('ExecResetPass', 'ListUsers')
    $script:Tenants = @(1..3 | ForEach-Object { [pscustomobject]@{ customerId = "tenant-$_"; defaultDomainName = "t$_.example.com" } })
    $script:AllIds = @('tenant-1', 'tenant-2', 'tenant-3')
    $script:GroupMembers = @{ g12 = @('tenant-1', 'tenant-2'); g3 = @('tenant-3') }
    $script:Filters = @(
        @{ N = 'none' }
        @{ N = 't1'; Q = 'tenant-1' }
        @{ N = 't2'; Q = 't2.example.com' }
        @{ N = 't3'; Q = 'tenant-3' }
        @{ N = 'AllTenants'; Q = 'AllTenants' }
        @{ N = 'unknown'; Q = 'unknown-tenant' }
        @{ N = 'g12'; G = 'g12' }
        @{ N = 'g3'; G = 'g3' }
        @{ N = 'q:t1 b:t2'; Q = 'tenant-1'; B = 'tenant-2' }
        @{ N = 'q:t1 b:t1'; Q = 'tenant-1'; B = 't1.example.com' }
    )

    function New-GroupItem($Id) { [pscustomobject]@{ type = 'Group'; value = $Id; label = $Id } }
    # Scope shape: what is stored on the role, what it reaches (tenants / groups) per the rules.
    $script:ScopeShapes = @{
        empty     = @{ Allowed = @(); Blocked = @(); Reach = @(); Groups = @(); BlockedIds = @() }
        t1        = @{ Allowed = @('tenant-1'); Blocked = @(); Reach = @('tenant-1'); Groups = @(); BlockedIds = @() }
        t2        = @{ Allowed = @('tenant-2'); Blocked = @(); Reach = @('tenant-2'); Groups = @(); BlockedIds = @() }
        all       = @{ Allowed = @('AllTenants'); Blocked = @(); Reach = @('tenant-1', 'tenant-2', 'tenant-3'); Groups = @(); BlockedIds = @(); Unrestricted = $true }
        allbut2   = @{ Allowed = @('AllTenants'); Blocked = @('tenant-2'); Reach = @('tenant-1', 'tenant-3'); Groups = @(); BlockedIds = @('tenant-2') }
        g12       = @{ Allowed = @((New-GroupItem 'g12')); Blocked = @(); Reach = @('tenant-1', 'tenant-2'); Groups = @('g12'); BlockedIds = @() }
        g3        = @{ Allowed = @((New-GroupItem 'g3')); Blocked = @(); Reach = @('tenant-3'); Groups = @('g3'); BlockedIds = @() }
        t1g3      = @{ Allowed = @('tenant-1', (New-GroupItem 'g3')); Blocked = @(); Reach = @('tenant-1', 'tenant-3'); Groups = @('g3'); BlockedIds = @() }
        stale     = @{ Allowed = @('tenant-gone'); Blocked = @(); Reach = @(); ListReach = @('tenant-gone'); Groups = @(); BlockedIds = @() }
        t1self    = @{ Allowed = @('tenant-1'); Blocked = @('tenant-1'); Reach = @(); Groups = @(); BlockedIds = @('tenant-1') }
        g12no2    = @{ Allowed = @((New-GroupItem 'g12')); Blocked = @('tenant-2'); Reach = @('tenant-1'); Groups = @('g12'); BlockedIds = @('tenant-2') }
        allbutg12 = @{ Allowed = @('AllTenants'); Blocked = @((New-GroupItem 'g12')); Reach = @('tenant-3'); Groups = @(); BlockedIds = @('tenant-1', 'tenant-2') }
    }
    $script:PermSets = @{
        none  = @('CIPP.Core.Read')
        read  = @('Identity.User.Read', 'Tenant.Standards.Read')
        write = @('Identity.User.Read', 'Identity.User.ReadWrite', 'Tenant.Standards.Read', 'Tenant.Standards.ReadWrite')
    }
    # Two role names per archetype, so a user can hold two different roles with the same definition.
    $script:RoleDefs = @{}
    $script:Model = @{}
    foreach ($Perm in @('none', 'read', 'write')) {
        foreach ($Scope in $script:ScopeShapes.Keys) {
            foreach ($Block in @('open', 'block')) {
                $Shape = $script:ScopeShapes[$Scope]
                foreach ($Name in @("$Perm-$Scope-$Block", "$Perm-$Scope-$Block~2")) {
                    $script:RoleDefs[$Name] = [pscustomobject]@{
                        Role             = $Name
                        Permissions      = $script:PermSets[$Perm]
                        AllowedTenants   = @($Shape.Allowed)
                        BlockedTenants   = @($Shape.Blocked)
                        BlockedEndpoints = @(if ($Block -eq 'block') { $script:BlockedEndpoints })
                    }
                    $script:Model[$Name] = @{ Perms = $script:PermSets[$Perm]; Shape = $Shape; Block = ($Block -eq 'block') }
                }
            }
        }
    }

    # ---- reference model ----
    function Test-ModelCovers($M, $Target, [bool]$IsGroup, [bool]$Write, [switch]$Block) {
        if ($M.Shape.Unrestricted) { return $true }
        if ($null -eq $Target) { return $true }
        if ($Target -eq 'AllTenants') { return -not $Write }
        if ($IsGroup) {
            $Members = $script:GroupMembers[$Target]
            if ($Block) { return ($M.Shape.Groups -contains $Target -or @($Members | Where-Object { $M.Shape.Reach -contains $_ }).Count -gt 0) }
            return ($M.Shape.Groups -contains $Target -and @($Members | Where-Object { $M.Shape.BlockedIds -contains $_ }).Count -eq 0)
        }
        $Id = ($script:Tenants | Where-Object { $_.customerId -eq $Target -or $_.defaultDomainName -eq $Target }).customerId
        if (-not $Id) { return [bool]$Block }
        return ($M.Shape.Reach -contains $Id)
    }
    function Test-BaseAllows($Base, $Permission) {
        $Rules = $script:CIPPBaseRoles.$Base
        $Allowed = @($Rules.include | Where-Object { $Permission -like $_ }).Count -gt 0
        $Allowed -and @($Rules.exclude | Where-Object { $Permission -like $_ }).Count -eq 0
    }
    function Get-ModelDecision($Base, [string[]]$Customs, $Op, $Filter) {
        $Permission = $script:Ops[$Op].Permission
        $Endpoint = $script:Ops[$Op].Endpoint
        if ($Base -in @('admin', 'superadmin')) { return $(if (Test-BaseAllows $Base $Permission) { 'allow' } else { 'deny' }) }
        if ($Base -and -not (Test-BaseAllows $Base $Permission)) { return 'deny' }
        if ($Customs.Count -eq 0) { return $(if ($Base) { 'allow' } else { 'deny' }) }
        $Granting = @($Customs | Where-Object { $script:Model[$_].Perms -contains $Permission })
        if ($Granting.Count -eq 0) { return 'deny' }
        $Targets = @(
            if ($Filter.G) { @{ Id = $Filter.G; IsGroup = $true } }
            if ($Filter.Q) { @{ Id = $Filter.Q; IsGroup = $false } }
            if ($Filter.B) { @{ Id = $Filter.B; IsGroup = $false } }
        )
        if ($Targets.Count -eq 0) { $Targets = @(@{ Id = $null; IsGroup = $false }) }
        $Write = $Permission -like '*Write'
        foreach ($Role in $Granting) {
            if (-not ($script:Model[$Role].Block -and $script:BlockedEndpoints -contains $Endpoint)) { continue }
            foreach ($T in $Targets) { if (Test-ModelCovers $script:Model[$Role] $T.Id $T.IsGroup $Write -Block) { return 'deny' } }
        }
        foreach ($T in $Targets) {
            if (@($Granting | Where-Object { Test-ModelCovers $script:Model[$_] $T.Id $T.IsGroup $Write }).Count -eq 0) { return 'deny' }
        }
        'allow'
    }
    function Get-ModelList($Base, [string[]]$Customs, $Op, [switch]$Groups) {
        $Permission = $script:Ops[$Op].Permission
        $Endpoint = $script:Ops[$Op].Endpoint
        $All = if ($Groups) { 'AllGroups' } else { 'AllTenants' }
        if ($Base -in @('admin', 'superadmin')) { return $All }
        if ($Base -and -not (Test-BaseAllows $Base $Permission)) { return '<refused>' }
        if ($Customs.Count -eq 0) { return $(if ($Base) { $All } else { '<refused>' }) }
        $Granting = @($Customs | Where-Object { $script:Model[$_].Perms -contains $Permission })
        $Blocking = @($Granting | Where-Object { $script:Model[$_].Block -and $script:BlockedEndpoints -contains $Endpoint })
        $Allowing = @($Granting | Where-Object { $Blocking -notcontains $_ })
        if ($Allowing.Count -eq 0 -or @($Blocking | Where-Object { $script:Model[$_].Shape.Unrestricted }).Count -gt 0) { return '' }
        if (@($Allowing | Where-Object { $script:Model[$_].Shape.Unrestricted }).Count -gt 0 -and $Blocking.Count -eq 0) { return $All }
        $Field = if ($Groups) { 'Groups' } else { 'ListReach' }
        $Take = { param($Role) $S = $script:Model[$Role].Shape; if (-not $Groups -and -not $S.ContainsKey('ListReach')) { $S.Reach } elseif ($Groups -and $S.Unrestricted) { @() } else { $S[$Field] } }
        $Minus = @(foreach ($R in $Blocking) { & $Take $R })
        (@(foreach ($R in $Allowing) { & $Take $R | Where-Object { $Minus -notcontains $_ } }) | Sort-Object -Unique) -join ','
    }

    # ---- the code under test ----
    function New-AccessRequest([string[]]$UserRoles, $Op, $Filter) {
        $Query = @{}; $Body = @{}
        if ($Filter.Q) { $Query['tenantFilter'] = $Filter.Q }
        if ($Filter.B) { $Body['tenantFilter'] = $Filter.B }
        if ($Filter.G) { $Body['tenantFilter'] = [pscustomobject]@{ type = 'Group'; value = $Filter.G; label = $Filter.G } }
        $Principal = @{ identityProvider = 'aad'; userId = 'u1'; userDetails = 'user@contoso.com'; userRoles = @('authenticated') + $UserRoles } | ConvertTo-Json -Compress
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = $script:Ops[$Op].Endpoint }
            Headers = @{ 'x-ms-client-principal' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Principal)); 'x-ms-client-principal-name' = 'user@contoso.com'; 'x-forwarded-for' = '1.2.3.4' }
            Query   = $Query
            Body    = $Body
        }
    }
    function Get-ActualDecision([string[]]$UserRoles, $Op, $Filter) {
        try { $null = Test-CIPPAccess -Request (New-AccessRequest $UserRoles $Op $Filter); 'allow' } catch { 'deny' }
    }
    function Get-ActualList([string[]]$UserRoles, $Op, [switch]$Groups) {
        $List = try {
            if ($Groups) { @(Test-CIPPAccess -Request (New-AccessRequest $UserRoles $Op @{}) -GroupList) } else { @(Test-CIPPAccess -Request (New-AccessRequest $UserRoles $Op @{}) -TenantList) }
        } catch { return '<refused>' }
        # Compare strings only: @($true) -contains 'AllTenants' is true in PowerShell.
        $Strings = @($List | ForEach-Object { if ($_ -is [string]) { $_ } else { "<$($_.GetType().Name):$_>" } })
        if ($Strings -ccontains 'AllTenants') { return 'AllTenants' }
        if ($Strings -ccontains 'AllGroups') { return 'AllGroups' }
        ($Strings | Sort-Object -Unique) -join ','
    }
    $script:CippAccessScopeRuleCache = @{}
}

Describe 'Test-CIPPAccess exhaustive role matrix' {
    It 'a user with no roles at all is refused everything' {
        foreach ($Op in $script:Ops.Keys) {
            foreach ($Filter in $script:Filters) { Get-ActualDecision @() $Op $Filter | Should -Be 'deny' }
        }
    }

    It '<_> alone' -ForEach @('readonly', 'editor', 'admin', 'superadmin') {
        $Mismatches = [System.Collections.Generic.List[string]]::new()
        foreach ($Op in $script:Ops.Keys) {
            foreach ($Filter in $script:Filters) {
                $Expected = Get-ModelDecision $_ @() $Op $Filter
                $Actual = Get-ActualDecision @($_) $Op $Filter
                if ($Actual -ne $Expected) { $Mismatches.Add("$Op $($Filter.N): expected $Expected, got $Actual") }
            }
            foreach ($Groups in @($false, $true)) {
                $Expected = Get-ModelList $_ @() $Op -Groups:$Groups
                $Actual = Get-ActualList @($_) $Op -Groups:$Groups
                if ($Actual -ne $Expected) { $Mismatches.Add("$Op $(if ($Groups) { 'group' } else { 'tenant' }) list: expected '$Expected', got '$Actual'") }
            }
        }
        $Mismatches | Should -BeNullOrEmpty
    }

    It '<Name>' -ForEach $script:Rows {
        $Mismatches = [System.Collections.Generic.List[string]]::new()
        foreach ($Customs in $Sets) {
            $Orders = @(, @(@($Base) + $Customs | Where-Object { $_ }))
            if ($Customs.Count -gt 1) { $Orders += , @(@($Customs[1], $Customs[0]) + @($Base) | Where-Object { $_ }) }
            foreach ($Op in $Ops) {
                foreach ($Filter in $script:Filters) {
                    $Expected = Get-ModelDecision $Base $Customs $Op $Filter
                    foreach ($Order in $Orders) {
                        $Actual = Get-ActualDecision $Order $Op $Filter
                        if ($Actual -ne $Expected) { $Mismatches.Add("[$($Order -join ',')] $Op $($Filter.N): expected $Expected, got $Actual") }
                    }
                }
                foreach ($Groups in @($false, $true)) {
                    $Expected = Get-ModelList $Base $Customs $Op -Groups:$Groups
                    foreach ($Order in $Orders) {
                        $Actual = Get-ActualList $Order $Op -Groups:$Groups
                        if ($Actual -ne $Expected) { $Mismatches.Add("[$($Order -join ',')] $Op $(if ($Groups) { 'group' } else { 'tenant' }) list: expected '$Expected', got '$Actual'") }
                    }
                }
            }
        }
        $Mismatches | Select-Object -First 15 | Should -BeNullOrEmpty -Because "$($Mismatches.Count) mismatches"
    }
}

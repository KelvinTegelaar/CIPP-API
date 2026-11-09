# Bulk "Add/Deploy" endpoints take their targets from selectedTenants in the body. A tenant-scoped role must
# not be able to reach tenants outside its scope that way, so each handler must narrow selectedTenants to the
# caller's allowed tenants (Test-CippAccess -TenantList). One handler is exercised behaviourally; the rest are
# guarded by source so the filter cannot be dropped and a new bulk endpoint fails here until it has one.

$script:EntrypointRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'

# Hands selectedTenants to the app handlers below instead of filtering it itself.
$script:DelegatingHandler = 'Invoke-ExecDeployAppTemplate.ps1'

# Every handler that reads a selectedTenants property, found by scan so the list cannot go stale.
$script:ScopedHandlers = @(
    Get-ChildItem -Path $script:EntrypointRoot -Recurse -Filter '*.ps1' |
        Where-Object { $_.Name -ne $script:DelegatingHandler -and (Get-Content $_.FullName -Raw) -match '\.selectedTenants\b' } |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
)

Describe 'Bulk endpoint tenant-scope source guard' {
    It 'finds the bulk handlers' -ForEach @(@{ Count = $script:ScopedHandlers.Count }) {
        # An empty scan would pass every case below vacuously.
        $Count | Should -BeGreaterThan 20
    }

    It 'narrows selectedTenants to the caller scope: <Name>' -ForEach $script:ScopedHandlers {
        (Get-Content $Path -Raw) | Should -Match 'Test-CippAccess -Request \$Request -TenantList|Resolve-CippBulkSelectedTenant -Request \$Request -SelectedTenants \$Request\.Body\.selectedTenants' `
            -Because "$Name exposes selectedTenants and must filter it against the caller's allowed tenants"
    }

    It 'the app template deploy only reaches handlers that resolve the caller scope, as the caller' -ForEach @(@{ Root = $script:EntrypointRoot; File = $script:DelegatingHandler }) {
        $Source = Get-Content (Get-ChildItem -Path $Root -Recurse -Filter $File).FullName -Raw
        # The handlers resolve scope from the request they are given, so it must carry the caller's headers.
        $Source | Should -Match 'Headers\s*=\s*\$Headers'
        $Called = [regex]::Matches($Source, 'Invoke-Add\w+(?= -Request \$MockRequest)').Value | Sort-Object -Unique
        $Called | Should -Not -BeNullOrEmpty
        foreach ($Handler in $Called) {
            $HandlerSource = Get-Content (Get-ChildItem -Path $Root -Recurse -Filter "$Handler.ps1").FullName -Raw
            $HandlerSource | Should -Match 'Resolve-CippBulkSelectedTenant -Request \$Request' -Because "$Handler is reachable from the app template deploy"
        }
    }

    It 'Resolve-CippBulkSelectedTenant filters against the caller scope' {
        $Path = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPCore/Public/Authentication/Resolve-CippBulkSelectedTenant.ps1'
        (Get-Content $Path -Raw) | Should -Match 'Test-CippAccess -Request \$Request -TenantList'
    }
}

Describe 'Invoke-AddConnectionFilter tenant-scope enforcement' {
    BeforeAll {
        $EntrypointRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
        $FunctionPath = Join-Path $EntrypointRoot 'Email-Exchange/Transport/Invoke-AddConnectionFilter.ps1'
        ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
            $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
        class HttpResponseContext { [int]$StatusCode; [object]$Body }
        function Test-CippAccess { param($Request, [switch]$TenantList) }
        function Get-Tenants { param([switch]$IncludeErrors) }
        function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
        function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
        function Get-CippException { param($Exception) @{} }
        function Get-CippBulkStatusCode { param($Total, $Failed) [System.Net.HttpStatusCode]::OK }
        . $FunctionPath

        $script:TwoTenants = @(
            [pscustomobject]@{ customerId = 'aaaaaaaa-0000-0000-0000-000000000000'; defaultDomainName = 'a.onmicrosoft.com' }
            [pscustomobject]@{ customerId = 'bbbbbbbb-0000-0000-0000-000000000000'; defaultDomainName = 'b.onmicrosoft.com' }
        )
        $script:Req = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'AddConnectionFilter' }
            Headers = @{}
            Body   = [pscustomobject]@{
                PowerShellCommand = '{"name":"cf"}'
                selectedTenants   = @([pscustomobject]@{ value = 'a.onmicrosoft.com' }, [pscustomobject]@{ value = 'b.onmicrosoft.com' })
            }
        }
    }

    BeforeEach {
        Mock Get-Tenants { $script:TwoTenants }
        Mock New-ExoRequest { }
    }

    It 'processes only the tenant the scoped role is allowed, dropping the out-of-scope one' {
        Mock Test-CippAccess { @('aaaaaaaa-0000-0000-0000-000000000000') }
        $null = Invoke-AddConnectionFilter -Request $script:Req
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'a.onmicrosoft.com' }
        Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $tenantid -eq 'b.onmicrosoft.com' }
    }

    It 'processes every selected tenant when the caller is unrestricted' {
        Mock Test-CippAccess { 'AllTenants' }
        $null = Invoke-AddConnectionFilter -Request $script:Req
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'a.onmicrosoft.com' }
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'b.onmicrosoft.com' }
    }
}

# selectedTenants entries carry a customerId and a defaultDomainName from the body; the write target must come
# from the tenant record resolved by customerId, and an AllTenants entry must not widen a scoped caller.
Describe '<Name> resolves selectedTenants against the tenant cache' -ForEach @(
    @{ Name = 'Invoke-AddEdgeApp'; Kind = 'Graph'; Body = @{} }
    @{ Name = 'Invoke-AddOfficeApp'; Kind = 'Graph'; Body = @{} }
    @{ Name = 'Invoke-AddStoreApp'; Kind = 'Queue'; Body = @{ ApplicationName = 'app'; PackageName = 'pkg' } }
    @{ Name = 'Invoke-AddWin32ScriptApp'; Kind = 'Queue'; Body = @{ ApplicationName = 'app'; installScript = 'echo' } }
    @{ Name = 'Invoke-AddChocoApp'; Kind = 'Queue'; Body = @{ ApplicationName = 'app'; PackageName = 'pkg' } }
    @{ Name = 'Invoke-AddMSPApp'; Kind = 'Queue'; Body = @{ DisplayName = 'app'; RMMName = @{ value = 'datto' }; params = @{} } }
) {
    BeforeAll {
        $BackendRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:PreviousRootPath = $env:CIPPRootPath
        $env:CIPPRootPath = $BackendRoot
        ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
            $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
        class HttpResponseContext { [int]$StatusCode; [object]$Body }
        function Test-CippAccess { param($Request, [switch]$TenantList) }
        function Test-CippAllTenantsBlocked { $false }
        function Get-Tenants { param([switch]$IncludeErrors) }
        function New-GraphGetRequest { param($Uri, $tenantid) }
        function New-GraphPostRequest { param($Uri, $tenantid, $Body, $Type) }
        function Get-CIPPEdgeAppBody { param($Config) }
        function Get-CIPPOfficeAppBody { param($Config) }
        function Set-CIPPAssignedApplication { param($ApplicationId, $TenantFilter, $Intent, $GroupName, $ExcludeGroup, $APIName, $Headers, $GroupIds, $ExcludeGroupIds) }
        function Get-CippTable { param($tablename) @{} }
        function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
        function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
        function ConvertTo-CIPPSafePwshArg { param($Value) "'$Value'" }
        function Get-CIPPMSPAppInstallCommand { param($RmmName, $Params, $Tenant, $PackageName) }
        function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
        function Get-CippException { param($Exception) @{} }
        function Get-CippBulkStatusCode { param($Total, $Failed) [System.Net.HttpStatusCode]::OK }
        . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Authentication/Resolve-CippBulkSelectedTenant.ps1')
        . (Join-Path $BackendRoot "Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/Applications/$Name.ps1")

        $script:IdA = 'aaaaaaaa-0000-0000-0000-000000000000'
        $script:IdB = 'bbbbbbbb-0000-0000-0000-000000000000'
        $script:TwoTenants = @(
            [pscustomobject]@{ customerId = $script:IdA; defaultDomainName = 'a.onmicrosoft.com' }
            [pscustomobject]@{ customerId = $script:IdB; defaultDomainName = 'b.onmicrosoft.com' }
        )
        function Invoke-Handler {
            param([object[]]$Selected)
            $Fields = $Body.Clone()
            $Fields.selectedTenants = $Selected
            $Body = [pscustomobject]$Fields
            $Req = [pscustomobject]@{ Params = @{ CIPPEndpoint = $Name }; Headers = @{}; Body = $Body }
            $null = & $Name -Request $Req
        }
        function Assert-Written {
            param([string]$Tenant, [int]$Times)
            if ($Kind -eq 'Graph') {
                Should -Invoke New-GraphPostRequest -Times $Times -Exactly -ParameterFilter { $tenantid -eq $Tenant }
            } else {
                Should -Invoke Add-CIPPAzDataTableEntity -Times $Times -Exactly -ParameterFilter { ($Entity.JSON | ConvertFrom-Json).tenant -eq $Tenant }
            }
        }
        function Assert-WriteCount {
            param([int]$Times)
            if ($Kind -eq 'Graph') {
                Should -Invoke New-GraphPostRequest -Times $Times -Exactly
            } else {
                Should -Invoke Add-CIPPAzDataTableEntity -Times $Times -Exactly
            }
        }
    }

    AfterAll {
        $env:CIPPRootPath = $script:PreviousRootPath
    }

    BeforeEach {
        Mock Get-Tenants { $script:TwoTenants }
        Mock New-GraphGetRequest { }
        Mock New-GraphPostRequest { [pscustomobject]@{ id = 'app-id' } }
        Mock Get-CIPPEdgeAppBody { @{ displayName = 'Edge' } }
        Mock Get-CIPPOfficeAppBody { @{ displayName = 'Office' } }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Get-CIPPMSPAppInstallCommand { [pscustomobject]@{ InstallCommandLine = 'install'; UninstallCommandLine = 'uninstall' } }
    }

    It 'does not write to another tenant paired with an allowed customerId' {
        Mock Test-CippAccess { @($script:IdA) }
        Invoke-Handler @([pscustomobject]@{ customerId = $script:IdA; defaultDomainName = 'b.onmicrosoft.com' })
        Assert-Written -Tenant 'b.onmicrosoft.com' -Times 0
        Assert-WriteCount -Times 0
    }

    It 'expands an AllTenants entry only to the scoped caller tenants' {
        Mock Test-CippAccess { @($script:IdA) }
        Invoke-Handler @([pscustomobject]@{ customerId = $script:IdA; defaultDomainName = 'AllTenants' })
        Assert-Written -Tenant 'a.onmicrosoft.com' -Times 1
        Assert-WriteCount -Times 1
    }

    It 'fails closed when the scoped caller has no allowed tenants' {
        Mock Test-CippAccess { @() }
        Invoke-Handler @([pscustomobject]@{ customerId = 'AllTenants'; defaultDomainName = 'AllTenants' })
        Assert-WriteCount -Times 0
    }

    It 'deploys an honest entry for the allowed tenant' {
        Mock Test-CippAccess { @($script:IdA) }
        Invoke-Handler @(
            [pscustomobject]@{ customerId = $script:IdA; defaultDomainName = 'a.onmicrosoft.com' }
            [pscustomobject]@{ customerId = $script:IdB; defaultDomainName = 'b.onmicrosoft.com' }
        )
        Assert-Written -Tenant 'a.onmicrosoft.com' -Times 1
        Assert-WriteCount -Times 1
    }

    It 'deploys every selected tenant when the caller is unrestricted' {
        Mock Test-CippAccess { 'AllTenants' }
        Invoke-Handler @(
            [pscustomobject]@{ customerId = $script:IdA; defaultDomainName = 'a.onmicrosoft.com' }
            [pscustomobject]@{ customerId = $script:IdB; defaultDomainName = 'b.onmicrosoft.com' }
        )
        Assert-Written -Tenant 'a.onmicrosoft.com' -Times 1
        Assert-Written -Tenant 'b.onmicrosoft.com' -Times 1
    }

    It 'keeps the AllTenants behaviour for an unrestricted caller' {
        Mock Test-CippAccess { 'AllTenants' }
        Invoke-Handler @([pscustomobject]@{ customerId = 'AllTenants'; defaultDomainName = 'AllTenants' })
        if ($Kind -eq 'Graph') {
            Assert-Written -Tenant 'a.onmicrosoft.com' -Times 1
            Assert-Written -Tenant 'b.onmicrosoft.com' -Times 1
        } else {
            Assert-Written -Tenant 'AllTenants' -Times 1
            Assert-WriteCount -Times 1
        }
    }

    It 'refuses an AllTenants entry when the caller''s roles block AllTenants (<Caller>)' -ForEach @(
        @{ Caller = 'unrestricted'; Allowed = @('AllTenants') }
        @{ Caller = 'scoped'; Allowed = @('aaaaaaaa-0000-0000-0000-000000000000') }
    ) {
        Mock Test-CippAccess { $Allowed }
        Mock Test-CippAllTenantsBlocked { $true }
        { Invoke-Handler @([pscustomobject]@{ customerId = 'AllTenants'; defaultDomainName = 'AllTenants' }) } |
            Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
        Assert-WriteCount -Times 0
    }

    It 'still deploys individually selected tenants when the caller''s roles block AllTenants' {
        Mock Test-CippAccess { 'AllTenants' }
        Mock Test-CippAllTenantsBlocked { $true }
        Invoke-Handler @([pscustomobject]@{ customerId = $script:IdA; defaultDomainName = 'a.onmicrosoft.com' })
        Assert-Written -Tenant 'a.onmicrosoft.com' -Times 1
    }
}

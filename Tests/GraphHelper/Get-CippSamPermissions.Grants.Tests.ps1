# The permission diff must reflect what is actually granted on the CIPP-SAM enterprise
# application, not what CIPP recorded that it applied. An instance with no admin consent
# reported "all the required permissions" while every Exchange call returned 401.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CippSamPermissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CippSamPermissions.ps1 under Modules/' }

    function Get-CippTable { param($tablename) @{ Context = 'stub' } }
    function Get-CippAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($Uri, $tenantid, $NoAuthCheck, $AsApp) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $NoAuthCheck, $asapp) }
    function Write-LogMessage { param($message, $tenant, $API, $sev, $Headers, $LogData) }

    . $FunctionPath

    $script:GraphAppId = '00000003-0000-0000-c000-000000000000'
    $script:GraphSpId = 'aaaaaaaa-0000-0000-0000-000000000001'
    $script:SamAppId = 'bbbbbbbb-0000-0000-0000-000000000002'
    $script:SamSpId = 'cccccccc-0000-0000-0000-000000000003'
    $script:ScopeId = '11111111-1111-1111-1111-111111111111'
    $script:ScopeName = 'Directory.Read.All'
    $script:RoleId = '22222222-2222-2222-2222-222222222222'
    $script:RoleName = 'Directory.ReadWrite.All'

    $script:ConfigRoot = Join-Path ([IO.Path]::GetTempPath()) ("samgrants-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path (Join-Path $script:ConfigRoot 'Config') -Force
    @{
        requiredResourceAccess = @(
            @{
                resourceAppId  = $script:GraphAppId
                resourceAccess = @(
                    @{ id = $script:ScopeId; type = 'Scope' },
                    @{ id = $script:RoleId; type = 'Role' }
                )
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $script:ConfigRoot 'Config/SAMManifest.json')
    '[]' | Set-Content -Path (Join-Path $script:ConfigRoot 'Config/AdditionalPermissions.json')

    $env:CIPPRootPath = $script:ConfigRoot
    $env:TenantID = '00000000-0000-0000-0000-000000000001'
    $env:ApplicationID = $script:SamAppId
}

AfterAll {
    Remove-Item -Path $script:ConfigRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-CippSamPermissions grant diff' {
    BeforeEach {
        $script:CippSamPermissionsCache = $null
        $script:CippSamPermissionsCacheTime = $null
        # Grants returned for the CIPP-SAM service principal; each test sets these.
        $script:AppRoleAssignments = @()
        $script:OAuthGrants = @()
        $script:GrantLookupThrows = $false

        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-CippAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            @(
                @{
                    body = [pscustomobject]@{
                        appId                     = $script:GraphAppId
                        displayName               = 'Microsoft Graph'
                        appRoles                  = @([pscustomobject]@{ id = $script:RoleId; value = $script:RoleName })
                        publishedPermissionScopes = @([pscustomobject]@{ id = $script:ScopeId; value = $script:ScopeName })
                    }
                }
            )
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($Uri -match 'servicePrincipals\?') {
                return @(
                    [pscustomobject]@{ id = $script:GraphSpId; appId = $script:GraphAppId; displayName = 'Microsoft Graph' },
                    [pscustomobject]@{ id = $script:SamSpId; appId = $script:SamAppId; displayName = 'CIPP-SAM' }
                )
            }
            if ($script:GrantLookupThrows) { throw 'Request failed with status code Forbidden' }
            if ($Uri -match "servicePrincipals\(appId='") { return [pscustomobject]@{ id = $script:SamSpId } }
            if ($Uri -match 'appRoleAssignments') { return $script:AppRoleAssignments }
            if ($Uri -match 'oauth2PermissionGrants') { return $script:OAuthGrants }
            return @()
        }
    }

    It 'reports nothing missing when both permissions are granted on the service principal' {
        $script:AppRoleAssignments = @([pscustomobject]@{ resourceId = $script:GraphSpId; appRoleId = $script:RoleId })
        $script:OAuthGrants = @([pscustomobject]@{ resourceId = $script:GraphSpId; scope = $script:ScopeName })

        $Result = Get-CippSamPermissions

        $Result.MissingPermissions.PSObject.Properties.Name | Should -BeNullOrEmpty
        $Result.GrantCheckFailed | Should -Not -BeTrue
    }

    It 'reports the delegated permission as missing when consent was never granted' {
        $script:AppRoleAssignments = @([pscustomobject]@{ resourceId = $script:GraphSpId; appRoleId = $script:RoleId })
        $script:OAuthGrants = @()

        $Result = Get-CippSamPermissions

        $Missing = $Result.MissingPermissions.($script:GraphAppId)
        @($Missing.delegatedPermissions.value) | Should -Contain $script:ScopeName
        @($Missing.applicationPermissions) | Should -BeNullOrEmpty
    }

    It 'reports the application permission as missing when its app role is not assigned' {
        $script:AppRoleAssignments = @()
        $script:OAuthGrants = @([pscustomobject]@{ resourceId = $script:GraphSpId; scope = $script:ScopeName })

        $Result = Get-CippSamPermissions

        $Missing = $Result.MissingPermissions.($script:GraphAppId)
        @($Missing.applicationPermissions.id) | Should -Contain $script:RoleId
        @($Missing.delegatedPermissions) | Should -BeNullOrEmpty
    }

    It 'reports everything missing when the app has no consent at all' {
        $Result = Get-CippSamPermissions

        $Missing = $Result.MissingPermissions.($script:GraphAppId)
        @($Missing.delegatedPermissions.value) | Should -Contain $script:ScopeName
        @($Missing.applicationPermissions.id) | Should -Contain $script:RoleId
    }

    It 'surfaces a grant lookup failure instead of reporting a clean result' {
        $script:GrantLookupThrows = $true

        $Result = Get-CippSamPermissions

        $Result.GrantCheckFailed | Should -BeTrue
        $Result.GrantCheckError | Should -Not -BeNullOrEmpty
    }

    It 'lists grants that are not in the effective set as extras' {
        $ExtraScope = 'Mail.Read'
        $script:AppRoleAssignments = @([pscustomobject]@{ resourceId = $script:GraphSpId; appRoleId = $script:RoleId })
        $script:OAuthGrants = @([pscustomobject]@{ resourceId = $script:GraphSpId; scope = "$($script:ScopeName) $ExtraScope" })

        $Result = Get-CippSamPermissions

        @($Result.PartnerAppDiff.($script:GraphAppId).extraDelegatedPermissions.value) | Should -Contain $ExtraScope
    }

    It 'skips the grant lookup entirely when called with -NoDiff' {
        $script:GrantLookupThrows = $true

        $Result = Get-CippSamPermissions -NoDiff

        $Result.MissingPermissions.PSObject.Properties.Name | Should -BeNullOrEmpty
        $Result.GrantCheckFailed | Should -Not -BeTrue
    }
}

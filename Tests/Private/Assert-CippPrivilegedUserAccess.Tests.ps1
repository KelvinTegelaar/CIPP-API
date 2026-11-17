BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Assert-CippPrivilegedUserAccess.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/PIM/Get-CIPPPrivilegedRoleTemplateIds.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function Get-CippRequestAllowedPermissions { }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $asapp, $Version) }
    function Get-CIPPPartnerTenant { param($PartnerTenantId, [switch]$IncludeDisabled) }
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    $script:SavedTenantId = $env:TenantID
    $env:TenantID = 'partner-tenant'

    $GlobalAdmin = '62e90394-69f5-4237-9190-012177145e10'
    $MessageCenterReader = '790c1fb9-7f7d-4f88-86a1-ef1f95c05c1b'
    $script:Active = @(
        [pscustomobject]@{ principalId = 'id-admin'; roleDefinitionId = $GlobalAdmin }
        [pscustomobject]@{ principalId = 'grp-active'; roleDefinitionId = $GlobalAdmin }
        [pscustomobject]@{ principalId = 'id-reader'; roleDefinitionId = $MessageCenterReader }
    )
    $script:Eligible = @(
        [pscustomobject]@{ principalId = 'id-elig'; roleDefinitionId = $GlobalAdmin }
        [pscustomobject]@{ principalId = 'grp-elig'; roleDefinitionId = $GlobalAdmin }
    )
    $script:Users = @{
        'admin@t'      = @{ id = 'id-admin' }
        'reader@t'     = @{ id = 'id-reader' }
        'elig@t'       = @{ id = 'id-elig' }
        'member@t'     = @{ id = 'id-member'; member = @('grp-other', 'grp-active') }
        'eligmember@t' = @{ id = 'id-eligmember'; member = @('grp-elig') }
        'owner@t'      = @{ id = 'id-owner'; owner = @('grp-active') }
        'pimgroup@t'   = @{ id = 'id-pimgroup' }
        'plain@t'      = @{ id = 'id-plain'; member = @('grp-other') }
        'agent@t'      = @{ id = 'id-agent'; member = @('grp-adminagents') }
        'helpdesk@t'   = @{ id = 'id-helpdesk'; member = @('grp-helpdeskagents') }
        'sales@t'      = @{ id = 'id-sales'; member = @('grp-salesagents') }
        'gdap@t'       = @{ id = 'id-gdap'; member = @('grp-gdap') }
        'gdapowner@t'  = @{ id = 'id-gdapowner'; owner = @('grp-gdap') }
        'guest_x.com#EXT#@t' = @{ id = 'id-guest'; member = @('grp-active') }
    }
    $script:GroupNames = @{
        'grp-adminagents'    = 'AdminAgents'
        'grp-helpdeskagents' = 'HelpdeskAgents'
        'grp-salesagents'    = 'SalesAgents'
        'grp-gdap'           = 'M365 GDAP Exchange Administrator'
    }
    $script:PimGroups = @{ 'id-pimgroup' = @('grp-active') }
}

AfterAll {
    $env:TenantID = $script:SavedTenantId
}

Describe 'Assert-CippPrivilegedUserAccess' {
    BeforeEach {
        $script:FailUrl = $null
        $script:FailStatus = 500
        $script:CippPrivilegedPrincipalMemo = $null
        $script:CippPrivilegedUserRestrictedStorage = $null
        $script:OrgId = 'customer-tenant'
        Mock Get-CIPPPartnerTenant { if ($PartnerTenantId -eq 'second-partner') { [pscustomobject]@{ RowKey = 'second-partner' } } }
        Mock Get-CIPPAzDataTableEntity { @([pscustomobject]@{ GroupId = 'grp-gdap'; roleDefinitionId = '29232cdf-9323-42fd-ade2-1d097af3e4de' }) }
        Mock Get-CippRequestAllowedPermissions { , @('Identity.User.ReadWrite') }
        Mock Test-CIPPStandardLicense { $true }
        Mock New-GraphBulkRequest {
            foreach ($R in $Requests) {
                $Status = 200
                $Body = switch -Regex ($R.url) {
                    '^roleManagement/directory/roleAssignments' { [pscustomobject]@{ value = $script:Active }; break }
                    '^roleManagement/directory/roleEligibilitySchedules' { [pscustomobject]@{ value = $script:Eligible }; break }
                    '^users/([^/?]+)\?' { $U = $script:Users[[uri]::UnescapeDataString($Matches[1])]; if (-not $U) { $Status = 404 }; [pscustomobject]@{ id = $U.id }; break }
                    '^organization' { [pscustomobject]@{ value = @([pscustomobject]@{ id = $script:OrgId }) }; break }
                    '^users/([^/?]+)/transitiveMemberOf' { [pscustomobject]@{ value = @($script:Users[[uri]::UnescapeDataString($Matches[1])].member | ForEach-Object { [pscustomobject]@{ id = $_; displayName = $script:GroupNames["$_"] } }) }; break }
                    '^users/([^/?]+)/ownedObjects' { [pscustomobject]@{ value = @($script:Users[[uri]::UnescapeDataString($Matches[1])].owner | ForEach-Object { [pscustomobject]@{ id = $_; displayName = $script:GroupNames["$_"] } }) }; break }
                    "principalId eq '([^']+)'" { [pscustomobject]@{ value = @($script:PimGroups[$Matches[1]] | ForEach-Object { [pscustomobject]@{ groupId = $_ } }) }; break }
                }
                if ($script:FailUrl -and $R.url -match $script:FailUrl) {
                    $Status = $script:FailStatus
                    $Body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'nope' } }
                }
                [pscustomobject]@{ id = $R.id; status = $Status; body = $Body }
            }
        }
    }

    Context 'who is checked' {
        It 'skips Graph when the caller holds the permission' {
            Mock Get-CippRequestAllowedPermissions { , @('Identity.User.ReadWrite', 'Identity.PrivilegedUser.ReadWrite') }
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'admin@t' } | Should -Not -Throw
            Should -Invoke New-GraphBulkRequest -Times 0
        }

        It 'skips Graph outside a request' {
            Mock Get-CippRequestAllowedPermissions { $null }
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'admin@t' } | Should -Not -Throw
            Should -Invoke New-GraphBulkRequest -Times 0
        }

        It 'checks outside a request when enforced for a restricted task' {
            Mock Get-CippRequestAllowedPermissions { $null }
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'admin@t' -Enforce } | Should -Throw '*admin@t holds*'
            Should -Invoke Get-CippRequestAllowedPermissions -Times 0
        }

        It 'looks each user up once however often it is named' {
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'admin@t', 'ADMIN@t', '' } | Should -Throw 'admin@t holds*'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests.url).Where({ $_ -like 'users/*' }).Count -eq 3 }
        }
    }

    Context 'how a privileged role is held' {
        It 'refuses <Name> with a 403' -ForEach @(
            @{ Name = 'an active role'; User = 'admin@t' }
            @{ Name = 'an active role through group membership'; User = 'member@t' }
            @{ Name = 'a PIM eligible role'; User = 'elig@t' }
            @{ Name = 'a PIM eligible role through group membership'; User = 'eligmember@t' }
            @{ Name = 'ownership of a privileged group'; User = 'owner@t' }
            @{ Name = 'PIM for Groups eligibility for a privileged group'; User = 'pimgroup@t' }
        ) {
            $Err = { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'plain@t', $User } | Should -Throw -PassThru
            $Err.Exception.Message | Should -BeLike "$User holds a privileged admin role*"
            Get-CippErrorStatusCode -ErrorRecord $Err | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        }

        It 'escapes a guest UPN so #EXT# stays part of the path' {
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'guest_x.com#EXT#@t' } | Should -Throw '*guest_x.com#EXT#@t holds*'
            Should -Invoke New-GraphBulkRequest -ParameterFilter { @($Requests.url).Where({ $_ -like 'users/guest_x.com%23EXT%23%40t/*' }).Count -eq 2 }
        }

        It 'allows users whose roles and groups are not privileged' {
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'plain@t', 'reader@t' } | Should -Not -Throw
        }

        It 'reads no PIM data in a tenant without PIM' {
            Mock Test-CIPPStandardLicense { $false }
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'elig@t', 'pimgroup@t' } | Should -Not -Throw
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'member@t' } | Should -Throw '*member@t holds*'
            Should -Invoke New-GraphBulkRequest -Times 0 -ParameterFilter { @($Requests.url).Where({ $_ -match 'roleEligibilitySchedules|privilegedAccess' }).Count -gt 0 }
        }

        It 'skips PIM for Groups when its permission is not consented' {
            $script:FailUrl = 'privilegedAccess/group'
            $script:FailStatus = 403
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'pimgroup@t' } | Should -Not -Throw
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'member@t' } | Should -Throw '*member@t holds*'
        }
    }

    Context 'partner tenants' {
        It 'refuses <User> in partner tenant <Org>' -ForEach @(
            @{ User = 'agent@t'; Org = 'partner-tenant' }
            @{ User = 'helpdesk@t'; Org = 'partner-tenant' }
            @{ User = 'gdap@t'; Org = 'partner-tenant' }
            @{ User = 'gdapowner@t'; Org = 'partner-tenant' }
            @{ User = 'agent@t'; Org = 'second-partner' }
        ) {
            $script:OrgId = $Org
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId $User } | Should -Throw "*$User holds*"
        }

        It 'allows SalesAgents, which carries no admin role' {
            $script:OrgId = 'partner-tenant'
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'sales@t' } | Should -Not -Throw
        }

        It 'ignores partner groups in a customer tenant, where AdminAgents is just a name' {
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'agent@t', 'gdap@t' } | Should -Not -Throw
            Should -Invoke Get-CIPPAzDataTableEntity -Times 0
        }
    }

    Context 'failing closed' {
        It 'refuses when <Url> fails' -ForEach @(
            @{ Url = '^organization'; Expect = '*Could not read the tenant id*' }
            @{ Url = 'roleAssignments'; Expect = '*Could not read the active role assignments*' }
            @{ Url = 'roleEligibilitySchedules'; Expect = '*Could not read the eligible role assignments*' }
            @{ Url = 'memberOf'; Expect = '*Could not check whether plain@t*' }
            @{ Url = 'privilegedAccess/group'; Expect = '*Could not check whether plain@t is eligible*' }
        ) {
            $script:FailUrl = $Url
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'plain@t' } | Should -Throw $Expect
        }

        It 'refuses a user it cannot find' {
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'gone@t' } | Should -Throw '*Could not check whether gone@t*'
        }

        It 'refuses when a role list came back partial' {
            Mock Test-CIPPStandardLicense { $false }
            Mock New-GraphBulkRequest { [pscustomobject]@{ id = 'active'; status = 200; PagingIncomplete = $true; body = [pscustomobject]@{ value = @() } } }
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'x' -Deleted } | Should -Throw '*Could not read the active*'
        }
    }

    Context 'bulk callers' {
        It 'returns the privileged users instead of refusing with -PassThru' {
            $Refused = @(Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'plain@t', 'admin@t', 'member@t' -PassThru)
            $Refused | Should -Be @('admin@t', 'member@t')
            @(Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'plain@t' -PassThru).Count | Should -Be 0
        }

        It 'reads the tenant role holders once a minute, but each user''s groups every time' {
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'plain@t' } | Should -Not -Throw
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'member@t' } | Should -Throw '*member@t holds*'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests.url).Where({ $_ -like 'roleManagement/*' }).Count -gt 0 }
            Should -Invoke New-GraphBulkRequest -Times 2 -Exactly -ParameterFilter { @($Requests.url).Where({ $_ -like '*/transitiveMemberOf/*' }).Count -gt 0 }

            $script:CippPrivilegedPrincipalMemo['t'].Expires = [datetime]::UtcNow.AddSeconds(-1)
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'plain@t' } | Should -Not -Throw
            Should -Invoke New-GraphBulkRequest -Times 2 -Exactly -ParameterFilter { @($Requests.url).Where({ $_ -like 'roleManagement/*' }).Count -gt 0 }
        }

        It 'checks inside a scheduled task queued without the permission' {
            Mock Get-CippRequestAllowedPermissions { $null }
            $script:CippPrivilegedUserRestrictedStorage = [System.Threading.AsyncLocal[bool]]::new()
            $script:CippPrivilegedUserRestrictedStorage.Value = $true
            @(Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'admin@t' -PassThru) | Should -Be @('admin@t')
            $script:CippPrivilegedUserRestrictedStorage.Value = $false
            @(Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'admin@t' -PassThru).Count | Should -Be 0
        }
    }

    Context 'deleted users' {
        It 'refuses a deleted user that held a privileged role, reading only the tenant role lists' {
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'id-admin' -Deleted } | Should -Throw '*id-admin holds*'
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'id-elig' -Deleted } | Should -Throw '*id-elig holds*'
            { Assert-CippPrivilegedUserAccess -TenantFilter 't' -UserId 'id-plain' -Deleted } | Should -Not -Throw
            Should -Invoke New-GraphBulkRequest -Times 0 -ParameterFilter { @($Requests.url).Where({ $_ -like 'users/*' }).Count -gt 0 }
        }
    }
}

Describe 'Get-CIPPPrivilegedRoleTemplateIds -Set EntraPrivileged' {
    It 'is a distinct list of role template ids and leaves the default set unchanged' {
        $Ids = @(Get-CIPPPrivilegedRoleTemplateIds -Set EntraPrivileged)
        $Ids.Count | Should -Be 35
        @($Ids | Sort-Object -Unique).Count | Should -Be 35
        $Ids | ForEach-Object { $_ | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' }
        @(Get-CIPPPrivilegedRoleTemplateIds).Count | Should -Be 18
    }
}

Describe 'Get-CIPPHttpFunctions with a comma-separated .ROLE' {
    BeforeAll {
        . (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules/CIPPCore/Public/Authentication/Get-CIPPHttpFunctions.ps1')
        New-Module -Name CIPPHTTP -ScriptBlock { function Invoke-ExecFakeReset { }; function Invoke-ListFake { } } | Import-Module -Force
        $script:CIPPFunctionPermissions = @{
            'Invoke-ExecFakeReset' = @{ Role = 'Identity.User.ReadWrite, Identity.PrivilegedUser.ReadWrite'; Functionality = 'Entrypoint' }
            'Invoke-ListFake'      = @{ Role = 'Identity.User.Read'; Functionality = 'Entrypoint' }
        }
    }
    AfterAll { Remove-Module CIPPHTTP -Force -ErrorAction SilentlyContinue }

    It 'puts every listed permission in the universe' {
        @(Get-CIPPHttpFunctions -ByRole).Permission | Should -Be @('Identity.PrivilegedUser.ReadWrite', 'Identity.User.Read', 'Identity.User.ReadWrite')
    }

    It 'lists the endpoint under each of its permissions' {
        $Groups = Get-CIPPHttpFunctions -ByRoleGroup
        $Groups.Identity.PrivilegedUser.ReadWrite.Name | Should -Be 'ExecFakeReset'
        $Groups.Identity.User.ReadWrite.Name | Should -Be 'ExecFakeReset'
    }
}

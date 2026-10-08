BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $skipTokenCache, $NoAuthCheck, $AsApp) }
    function New-GraphPostRequest { [CmdletBinding()] param($uri, $type, $tenantid, $body, $AsApp, $NoAuthCheck) }
    function New-GraphBulkRequest { [CmdletBinding()] param($Requests, $tenantid, $NoAuthCheck) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $sev, $LogData) }
    function Clear-CippTokenCache { [CmdletBinding()] param($TenantFilter) }
    function Get-NormalizedError { [CmdletBinding()] param($message) $message }
    function Add-CIPPDelegatedPermission { [CmdletBinding()] param($RequiredResourceAccess, $ApplicationId, $TenantFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPApplicationPermission.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPApplicationCopy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:AppId = '053161e9-fd87-40dc-8cd9-74b8f17cd74f'
    $script:Graph = '00000003-0000-0000-c000-000000000000'
    $script:Access = @([pscustomobject]@{ resourceAppId = $script:Graph; resourceAccess = @([pscustomobject]@{ id = 'role-1'; type = 'Role' }) })
}

Describe 'Add-CIPPApplicationPermission service principal lookup' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock Write-LogMessage {}
        Mock Clear-CippTokenCache {}
        Mock New-GraphBulkRequest { @([pscustomobject]@{ id = '1'; status = 201 }) }
        $script:Lookups = 0
    }

    It 'waits for a newly created service principal instead of querying an empty id' {
        Mock New-GraphGETRequest {
            if ($uri -like "*servicePrincipals(appId='$script:AppId')*") {
                $script:Lookups++
                if ($script:Lookups -lt 3) { throw 'Resource does not exist' }
                return [pscustomobject]@{ appId = $script:AppId; id = 'new-sp'; displayName = 'Halo' }
            }
            if ($uri -like '*servicePrincipals[?]*') { return @([pscustomobject]@{ appId = $script:Graph; id = 'graph-sp' }) }
            @()
        }
        Add-CIPPApplicationPermission -RequiredResourceAccess $script:Access -ApplicationId $script:AppId -TenantFilter $script:Tenant
        Should -Invoke New-GraphGETRequest -ParameterFilter { $uri -like '*servicePrincipals/new-sp/appRoleAssignments' }
        Should -Invoke New-GraphGETRequest -Times 0 -ParameterFilter { $uri -like '*servicePrincipals//appRoleAssignments' }
    }

    It 'fails with a clear message when the service principal never appears' {
        Mock New-GraphGETRequest {
            if ($uri -like '*servicePrincipals(appId=*') { throw 'Resource does not exist' }
            @()
        }
        { Add-CIPPApplicationPermission -RequiredResourceAccess $script:Access -ApplicationId $script:AppId -TenantFilter $script:Tenant } |
            Should -Throw "*$script:AppId was not found*"
        Should -Invoke New-GraphGETRequest -Times 0 -ParameterFilter { $uri -like '*appRoleAssignments' }
    }
}

Describe 'New-CIPPApplicationCopy' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPApplicationPermission {}
        Mock Add-CIPPDelegatedPermission {}
        Mock New-GraphPostRequest {}
        Mock New-GraphGETRequest {
            switch -Wildcard ($uri) {
                '*v1.0/servicePrincipals?*' { @([pscustomobject]@{ appId = $script:AppId; id = 'partner-sp' }, [pscustomobject]@{ appId = $script:Graph; id = 'partner-graph' }) }
                '*applications(appId=*' { throw 'not found' }
                '*oauth2PermissionGrants' { @([pscustomobject]@{ resourceId = 'partner-graph'; scope = 'User.Read.All' }) }
                '*appRoleAssignments' { @([pscustomobject]@{ resourceId = 'partner-graph'; appRoleId = 'role-1' }) }
                default { @() }
            }
        }
    }

    It 'passes the delegated grants, not the app roles, for an app that only exists as a service principal' {
        New-CIPPApplicationCopy -App $script:AppId -Tenant $script:Tenant
        Should -Invoke Add-CIPPDelegatedPermission -Times 1 -ParameterFilter { $RequiredResourceAccess.resourceAccess.type -eq 'Scope' -and $RequiredResourceAccess.resourceAccess.id -eq 'User.Read.All' }
    }
}

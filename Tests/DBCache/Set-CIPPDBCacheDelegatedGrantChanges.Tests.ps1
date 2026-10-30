# Pester tests for Set-CIPPDBCacheDelegatedGrantChanges and ConvertFrom-CIPPGrantAuditEvent
# Each added grant is kept with its client app, resource API, consent type and who added it; an empty log is
# recorded as an empty set and a failed read writes nothing and rethrows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/ConvertFrom-CIPPGrantAuditEvent.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDelegatedGrantChanges.ps1')

    function script:New-GrantEvent {
        param($Activity = 'Add delegated permission grant', $Actor, $ConsentType = 'Principal')
        [pscustomobject]@{
            id                  = 'evt-1'
            activityDateTime    = '2026-10-20T10:00:00Z'
            activityDisplayName = $Activity
            initiatedBy         = $Actor
            targetResources     = @(
                [pscustomobject]@{
                    id = 'res-graph'; type = 'ServicePrincipal'; displayName = 'Microsoft Graph'
                    modifiedProperties = @(
                        [pscustomobject]@{ displayName = 'DelegatedPermissionGrant.Scope'; oldValue = $null; newValue = '" Mail.Read offline_access"' }
                        [pscustomobject]@{ displayName = 'DelegatedPermissionGrant.ConsentType'; oldValue = $null; newValue = "`"$ConsentType`"" }
                        [pscustomobject]@{ displayName = 'ServicePrincipal.ObjectID'; oldValue = $null; newValue = '"sp-client"' }
                    )
                }
            )
        }
    }
}

Describe 'ConvertFrom-CIPPGrantAuditEvent' {
    It 'returns the client, resource, consent type and scopes of a grant an app added' {
        $Actor = [pscustomobject]@{ app = [pscustomobject]@{ appId = 'app-x'; displayName = 'Other App'; servicePrincipalId = 'sp-x' } }

        $Rows = @(ConvertFrom-CIPPGrantAuditEvent -Events @(script:New-GrantEvent -Actor $Actor))

        $Rows.Count | Should -Be 1
        $Rows[0].clientId | Should -BeExactly 'sp-client'
        $Rows[0].resourceId | Should -BeExactly 'res-graph'
        $Rows[0].consentType | Should -BeExactly 'Principal'
        $Rows[0].scope | Should -BeExactly 'Mail.Read offline_access'
        $Rows[0].initiatedByType | Should -BeExactly 'Application'
        $Rows[0].initiatedByName | Should -BeExactly 'Other App'
        $Rows[0].initiatedByServicePrincipalId | Should -BeExactly 'sp-x'
    }

    It 'names the user who consented' {
        $Actor = [pscustomobject]@{ user = [pscustomobject]@{ id = 'u1'; userPrincipalName = 'user@contoso.com' } }

        $Rows = @(ConvertFrom-CIPPGrantAuditEvent -Events @(script:New-GrantEvent -Actor $Actor))

        $Rows[0].initiatedByType | Should -BeExactly 'User'
        $Rows[0].initiatedByName | Should -BeExactly 'user@contoso.com'
    }

    It 'ignores other events' {
        @(ConvertFrom-CIPPGrantAuditEvent -Events @(script:New-GrantEvent -Activity 'Remove delegated permission grant')).Count | Should -Be 0
    }
}

Describe 'Set-CIPPDBCacheDelegatedGrantChanges' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
    }

    It 'reads 30 days of added delegated grants app-only and caches them' {
        Mock New-GraphGetRequest { script:New-GrantEvent }

        Set-CIPPDBCacheDelegatedGrantChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*directoryAudits?`$filter=activityDisplayName eq 'Add delegated permission grant' and activityDateTime ge *" -and $AsApp }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'DelegatedGrantChanges' -and @($Data).Count -eq 1 -and -not $ClearOnEmpty }
    }

    It 'records an empty set when no grant was added' {
        Mock New-GraphGetRequest { }

        Set-CIPPDBCacheDelegatedGrantChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'writes nothing and rethrows when the audit log cannot be read' {
        Mock New-GraphGetRequest { throw 'Forbidden' }

        { Set-CIPPDBCacheDelegatedGrantChanges -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*Forbidden*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }
}

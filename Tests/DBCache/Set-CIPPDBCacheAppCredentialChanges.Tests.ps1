# Pester tests for Set-CIPPDBCacheAppCredentialChanges and ConvertFrom-CIPPCredentialAuditEvent
# Credentials an event added (present after the change, not before) or removed are kept, with who changed
# them; an empty log is recorded as an empty set and a failed read writes nothing and rethrows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/ConvertFrom-CIPPCredentialAuditEvent.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheAppCredentialChanges.ps1')

    function script:New-Event {
        param($Actor, $Old = '[]', $New)
        [pscustomobject]@{
            activityDateTime    = '2026-10-20T10:00:00Z'
            activityDisplayName = 'Update application - Certificates and secrets management '
            initiatedBy         = $Actor
            targetResources     = @([pscustomobject]@{
                    id = 'reg-1'; type = 'Application'; displayName = 'Script'
                    modifiedProperties = @(
                        [pscustomobject]@{ displayName = 'DisplayName'; oldValue = '"a"'; newValue = '"b"' }
                        [pscustomobject]@{ displayName = 'KeyDescription'; oldValue = $Old; newValue = $New }
                    )
                })
        }
    }
}

Describe 'ConvertFrom-CIPPCredentialAuditEvent' {
    It 'returns only the keys an event added, with the app that added them' {
        $Event = script:New-Event -Actor ([pscustomobject]@{ app = [pscustomobject]@{ appId = 'app-x'; displayName = 'Other App'; servicePrincipalId = 'sp-x' } }) `
            -Old '["[KeyIdentifier=old-1,KeyType=Password,KeyUsage=Verify,DisplayName=a]"]' `
            -New '["[KeyIdentifier=old-1,KeyType=Password,KeyUsage=Verify,DisplayName=a]","[KeyIdentifier=new-1,KeyType=AsymmetricX509Cert,KeyUsage=Verify,DisplayName=b]"]'

        $Rows = @(ConvertFrom-CIPPCredentialAuditEvent -Events @($Event))

        $Rows.Count | Should -Be 1
        $Rows[0].id | Should -BeExactly 'reg-1-new-1'
        $Rows[0].keyType | Should -BeExactly 'AsymmetricX509Cert'
        $Rows[0].initiatedByType | Should -BeExactly 'Application'
        $Rows[0].initiatedByName | Should -BeExactly 'Other App'
    }

    It 'names the user when a person added the key, and records removals apart from additions' {
        $User = [pscustomobject]@{ user = [pscustomobject]@{ id = 'u1'; userPrincipalName = 'admin@contoso.com' } }
        $Added = @(ConvertFrom-CIPPCredentialAuditEvent -Events @(script:New-Event -Actor $User -New '["[KeyIdentifier=k,KeyType=Password,KeyUsage=Verify,DisplayName=a]"]'))
        $Removed = @(ConvertFrom-CIPPCredentialAuditEvent -Events @(script:New-Event -Actor $User -Old '["[KeyIdentifier=k,KeyType=Password,KeyUsage=Verify,DisplayName=a]"]' -New '[]'))

        $Added[0].action | Should -BeExactly 'Added'
        $Added[0].initiatedByType | Should -BeExactly 'User'
        $Added[0].initiatedByName | Should -BeExactly 'admin@contoso.com'
        $Removed.Count | Should -Be 1
        $Removed[0].action | Should -BeExactly 'Removed'
        $Removed[0].id | Should -BeExactly 'reg-1-k-Removed'
        $Removed[0].keyUsage | Should -BeExactly 'Verify'
    }
}

Describe 'Set-CIPPDBCacheAppCredentialChanges' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
    }

    It 'reads 30 days of ApplicationManagement events app-only and caches the added credentials' {
        Mock New-GraphGetRequest { script:New-Event -Actor $null -New '["[KeyIdentifier=k,KeyType=Password,KeyUsage=Verify,DisplayName=a]"]' }

        Set-CIPPDBCacheAppCredentialChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*directoryAudits?`$filter=category eq 'ApplicationManagement' and activityDateTime ge *" -and $AsApp }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'AppCredentialChanges' -and @($Data).Count -eq 1 -and -not $ClearOnEmpty }
    }

    It 'records an empty set when nothing was added' {
        Mock New-GraphGetRequest { }

        Set-CIPPDBCacheAppCredentialChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'writes nothing and rethrows when the audit log cannot be read' {
        Mock New-GraphGetRequest { throw 'Forbidden' }

        { Set-CIPPDBCacheAppCredentialChanges -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*Forbidden*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }
}

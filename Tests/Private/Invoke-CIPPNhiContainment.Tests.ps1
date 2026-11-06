BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPBecReport { param($Kind, $TenantFilter, $CaseId, [switch]$IncludeResults) }
    function Set-CIPPBecReport { param($Kind, $TenantFilter, $CaseId, $Properties) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    function Set-CippBecCaseContext { param($CaseId) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/NHI/Get-CIPPNhiContainmentActions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/NHI/Invoke-CIPPNhiContainment.ps1')

    function script:New-Run {
        param([switch]$ManagedIdentity)
        [pscustomobject]@{
            CaseId      = 'NHI-1'
            Status      = 'Completed'
            Containment = @([pscustomobject]@{ At = '2026-11-01T00:00:00Z'; Kind = 'Containment'; Actions = @('ConfirmCompromised') })
            Results     = [pscustomobject]@{
                ServicePrincipalId = 'sp-1'
                DisplayName        = 'Invoice Sync'
                Subject            = [pscustomobject]@{ AppRegistrationId = 'reg-1'; IsManagedIdentity = [bool]$ManagedIdentity; AzureResourceId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Web/sites/app1' }
                FlaggedKeyIds      = @('key-new', 'fic-bad')
                Exposure           = [pscustomobject]@{ CredentialDetails = @(
                        [pscustomobject]@{ Location = 'App registration'; Type = 'Certificate'; KeyId = 'key-old'; Flags = @() }
                        [pscustomobject]@{ Location = 'Enterprise app'; Type = 'Secret'; KeyId = 'key-new'; DisplayName = 'x'; Flags = @('AddedByApp') }
                        [pscustomobject]@{ Location = 'App registration'; Type = 'Certificate'; KeyId = 'cert-new'; Flags = @('Backdated') }
                        [pscustomobject]@{ Location = 'App registration'; Type = 'Federated'; KeyId = 'fic-bad'; DisplayName = 'oidc'; Flags = @('UntrustedIssuer') }
                    ) }
                Owners             = @([pscustomobject]@{ Id = 'u2'; UserPrincipalName = 'guest#EXT#@contoso.com'; OwnerOf = 'App registration' })
                AppRoleAssignments = @(
                    [pscustomobject]@{ Id = 'ara-new'; ResourceDisplayName = 'Microsoft Graph'; Permission = 'Mail.Read'; InWindow = $true }
                    [pscustomobject]@{ Id = 'ara-old'; ResourceDisplayName = 'Microsoft Graph'; Permission = 'User.Read.All'; InWindow = $false }
                )
                DelegatedGrants    = @()
                DirectoryRoles     = @()
                DirectoryActions   = @(
                    [pscustomobject]@{ Kind = 'AppPersistence'; CreatedApp = $true; InWindow = $true; TargetServicePrincipalId = 'sp-backdoor'; TargetDisplayName = 'Teams Sync'; TargetProtected = $false }
                    [pscustomobject]@{ Kind = 'AppPersistence'; Lateral = $true; InWindow = $true; TargetServicePrincipalId = 'sp-graph'; TargetDisplayName = 'Microsoft Graph'; TargetProtected = $true }
                    [pscustomobject]@{ Kind = 'AppPersistence'; Lateral = $true; InWindow = $false; TargetServicePrincipalId = 'sp-old'; TargetDisplayName = 'Old Connector'; TargetProtected = $false }
                    [pscustomobject]@{ Kind = 'Directory'; InWindow = $true; TargetServicePrincipalId = 'sp-not-persistence' }
                    [pscustomobject]@{ Kind = 'Elevation'; ElevationId = 'e-approle'; ElevationType = 'Application permission'; Permission = 'Microsoft Graph Mail.ReadWrite'; ElevationRoleId = 'role-mrw'; ResourceId = 'res-graph'; RecipientId = 'sp-backdoor'; RecipientName = 'Teams Sync'; Impact = 'Critical'; InWindow = $true }
                    [pscustomobject]@{ Kind = 'Elevation'; ElevationId = 'e-role'; ElevationType = 'Directory role'; Permission = 'Global Administrator'; ElevationRoleId = 'ga-template'; RecipientId = 'u-helpdesk'; RecipientName = 'helpdesk@contoso.com'; Impact = 'Critical'; InWindow = $true }
                    [pscustomobject]@{ Kind = 'Elevation'; ElevationId = 'e-grant'; ElevationType = 'Delegated permission'; Permission = 'Microsoft Graph Mail.ReadWrite'; Scopes = 'Mail.ReadWrite'; ConsentType = 'AllPrincipals'; ResourceId = 'res-graph'; RecipientId = 'sp-backdoor'; Impact = 'Medium'; InWindow = $true }
                )
            }
        }
    }
}

Describe 'Invoke-CIPPNhiContainment' {
    BeforeEach {
        Mock Get-CIPPBecReport { script:New-Run }
        $script:History = $null
        Mock Set-CIPPBecReport { $script:History = $Properties.Containment }
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        Mock New-GraphPOSTRequest { $script:Calls.Add([pscustomobject]@{ Uri = $uri; Type = $type; Body = $body }) }
        Mock New-GraphGetRequest { [pscustomobject]@{ keyCredentials = @([pscustomobject]@{ keyId = 'key-old' }, [pscustomobject]@{ keyId = 'cert-new' }) } }
        Mock Write-LogMessage { }
    }

    It 'refuses Critical actions without confirmation' {
        { Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' } | Should -Throw '*Confirmation is required*'
        $script:Calls.Count | Should -Be 0
    }

    It 'disables the app and removes only the flagged credentials by default, never the app''s own' {
        $Rows = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Confirmed

        $script:Calls[0].Uri | Should -BeLike '*/servicePrincipals/sp-1'
        $script:Calls[0].Body | Should -BeExactly '{"accountEnabled":false}'
        $Removal = $script:Calls | Where-Object Uri -Like '*/servicePrincipals/sp-1/removePassword'
        $Removal.Body | Should -BeExactly '{"keyId":"key-new"}'
        @($script:Calls | Where-Object Uri -Like '*/applications/reg-1').Count | Should -Be 0 -Because 'neither certificate on the registration was flagged'
        @($Rows | Where-Object state -EQ 'success').Count | Should -Be 2
        @($Rows).Target | Should -Not -Contain 'fic-bad' -Because 'federated credentials have their own action'
    }

    It 'replaces keyCredentials without the selected certificates' {
        $null = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'RemoveCredentials' -Parameters @{ CredentialKeyIds = @('cert-new') } -Confirmed

        $Patch = $script:Calls | Where-Object { $_.Uri -like '*/applications/reg-1' -and $_.Type -eq 'PATCH' }
        ($Patch.Body | ConvertFrom-Json).keyCredentials.keyId | Should -Be @('key-old')
    }

    It 'revokes the permissions granted in the window and removes the flagged federated credential' {
        $null = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'RevokeAppRoleAssignments', 'RemoveFederatedCredentials' -Confirmed

        @($script:Calls | Where-Object Type -EQ 'DELETE').Uri | Should -Be @(
            'https://graph.microsoft.com/v1.0/applications/reg-1/federatedIdentityCredentials/fic-bad'
            'https://graph.microsoft.com/v1.0/servicePrincipals/sp-1/appRoleAssignments/ara-new'
        )
    }

    It 'removes owners only when selected' {
        $Rows = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'RemoveOwners'
        $Rows[0].state | Should -BeExactly 'info'
        $script:Calls.Count | Should -Be 0

        $null = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'RemoveOwners' -Parameters @{ OwnerIds = @(@{ value = 'u2' }) }
        $script:Calls[0].Uri | Should -BeExactly 'https://graph.microsoft.com/v1.0/applications/reg-1/owners/u2/$ref'
    }

    It 'points a managed identity at Azure instead of disabling it' {
        Mock Get-CIPPBecReport { script:New-Run -ManagedIdentity }

        $Rows = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'DisableServicePrincipal' -Confirmed

        $Rows[0].state | Should -BeExactly 'warning'
        $Rows[0].resultText | Should -BeLike '*Microsoft.Web/sites/app1*'
        $script:Calls.Count | Should -Be 0
    }

    It 'keeps going when one action fails, and appends the run to the case history' {
        Mock New-GraphPOSTRequest { throw 'Insufficient privileges' } -ParameterFilter { $uri -like '*confirmCompromised' }

        $Rows = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'ConfirmCompromised', 'LockAppInstanceProperties'

        ($Rows | Where-Object Action -EQ 'ConfirmCompromised').state | Should -BeExactly 'error'
        ($Rows | Where-Object Action -EQ 'LockAppInstanceProperties').state | Should -BeExactly 'success'
        @($script:History).Count | Should -Be 2
        $script:History[-1].Actions | Should -Be @('ConfirmCompromised', 'LockAppInstanceProperties')
    }

    It 'disables the apps it created or put credentials on in the window, never Microsoft''s, nor an id the case did not find' {
        $Rows = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'DisablePersistenceApps' -Confirmed

        @($script:Calls.Uri) | Should -Be @('https://graph.microsoft.com/v1.0/servicePrincipals/sp-backdoor') -Because 'Microsoft Graph is protected and the old connector is outside the window'
        $Rows[0].resultText | Should -BeLike 'Disabled Teams Sync, which Invoice Sync created'

        $script:Calls.Clear()
        $Picked = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'DisablePersistenceApps' -Parameters @{ PersistenceServicePrincipalIds = @('sp-old', 'sp-graph', 'sp-not-persistence') } -Confirmed

        @($script:Calls.Uri) | Should -Be @('https://graph.microsoft.com/v1.0/servicePrincipals/sp-old')
        ($Picked | Where-Object Target -EQ 'sp-graph').state | Should -BeExactly 'warning'
        ($Picked | Where-Object Target -EQ 'sp-not-persistence').state | Should -BeExactly 'warning'
    }

    It 'revokes the high-impact access it granted in the window, and only the delegated scopes it added' {
        Mock New-GraphGetRequest {
            if ($uri -like '*/servicePrincipals/sp-backdoor/appRoleAssignments') { return @([pscustomobject]@{ id = 'ara-mrw'; appRoleId = 'role-mrw'; resourceId = 'res-graph' }, [pscustomobject]@{ id = 'ara-other'; appRoleId = 'role-x'; resourceId = 'res-graph' }) }
            if ($uri -like '*roleAssignments?*') { return @([pscustomobject]@{ id = 'ra-ga' }) }
            if ($uri -like '*oauth2PermissionGrants?*') { return @([pscustomobject]@{ id = 'g1'; consentType = 'AllPrincipals'; scope = 'User.Read Mail.ReadWrite' }) }
        }

        $Rows = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'RevokeElevation' -Confirmed

        @($script:Calls | Where-Object Type -EQ 'DELETE').Uri | Should -Be @(
            'https://graph.microsoft.com/v1.0/servicePrincipals/sp-backdoor/appRoleAssignments/ara-mrw'
            'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/ra-ga'
        ) -Because 'the medium-impact delegated grant is not a default target'
        @($Rows | Where-Object state -EQ 'success').Count | Should -Be 2

        $script:Calls.Clear()
        $null = Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'RevokeElevation' -Parameters @{ ElevationIds = @('e-grant') } -Confirmed
        $Patch = $script:Calls | Where-Object Type -EQ 'PATCH'
        $Patch.Uri | Should -BeExactly 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants/g1'
        ($Patch.Body | ConvertFrom-Json).scope | Should -BeExactly 'User.Read' -Because 'scopes others consented to stay'
    }

    It 'refuses a case that has not completed' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Running' } }
        { Invoke-CIPPNhiContainment -TenantFilter 'contoso.com' -CaseId 'NHI-1' -Actions 'ConfirmCompromised' } | Should -Throw '*has not completed*'
    }
}

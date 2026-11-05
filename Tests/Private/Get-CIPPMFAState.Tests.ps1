# Pester tests for Get-CIPPMFAState — guest/external user CA coverage.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPMFAState.ps1')

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $ErrorAction) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $Version) }
    function Write-LogMessage { param($headers, $API, $Tenant, $message, $Sev, $LogData) }

    $script:TenantA = 'aaaaaaaa-0000-0000-0000-000000000001'
    $script:TenantB = 'bbbbbbbb-0000-0000-0000-000000000002'
    $script:Users = @(
        [pscustomobject]@{ id = 'u-member'; userPrincipalName = 'alice@contoso.com'; displayName = 'Alice'; accountEnabled = $true; assignedLicenses = @(); userType = 'Member' }
        [pscustomobject]@{ id = 'u-b2bguest'; userPrincipalName = 'bob_fabrikam.com#EXT#@contoso.com'; displayName = 'Bob'; accountEnabled = $true; assignedLicenses = @(); userType = 'Guest' }
        [pscustomobject]@{ id = 'u-intguest'; userPrincipalName = 'carol@contoso.com'; displayName = 'Carol'; accountEnabled = $true; assignedLicenses = @(); userType = 'Guest' }
        [pscustomobject]@{ id = 'u-extmember'; userPrincipalName = 'dave_tailspin.com#EXT#@contoso.com'; displayName = 'Dave'; accountEnabled = $true; assignedLicenses = @(); userType = 'Member' }
    )

    function New-TestPolicy {
        param ([hashtable]$Users)
        $UserBlock = @{
            includeUsers  = @()
            excludeUsers  = @()
            includeGroups = @()
            excludeGroups = @()
            includeRoles  = @()
            excludeRoles  = @()
        }
        foreach ($Key in $Users.Keys) { $UserBlock[$Key] = $Users[$Key] }
        [pscustomobject]@{
            id            = 'policy-1'
            displayName   = 'Guest MFA'
            state         = 'enabled'
            grantControls = [pscustomobject]@{ builtInControls = @('mfa') }
            conditions    = [pscustomobject]@{
                applications = [pscustomobject]@{ includeApplications = @('All') }
                users        = [pscustomobject]$UserBlock
            }
        }
    }

    function Get-TestMFAState {
        param ($Policy)
        Mock -CommandName New-GraphGetRequest -MockWith { $script:Users } -ParameterFilter { $uri -like '*/users?*' }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ IsEnabled = $false } } -ParameterFilter { $uri -like '*identitySecurityDefaultsEnforcementPolicy*' }
        Mock -CommandName New-GraphGetRequest -MockWith { $script:Users | ForEach-Object { [pscustomobject]@{ userPrincipalName = $_.userPrincipalName; isMfaRegistered = $true; isMfaCapable = $true; methodsRegistered = @() } } } -ParameterFilter { $uri -like '*userRegistrationDetails*' }
        Mock -CommandName New-GraphGetRequest -MockWith { $Policy } -ParameterFilter { $uri -like '*/conditionalAccess/policies*' }
        $Rows = @(Get-CIPPMFAState -TenantFilter 'contoso.com')
        $Map = @{}
        foreach ($Row in $Rows) { $Map[$Row.ID] = $Row }
        return $Map
    }
}

Describe 'Get-CIPPMFAState guest coverage' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        # fabrikam.com (Bob, B2B guest) -> tenant A; tailspin.com (Dave, #EXT# member) -> tenant B
        Mock -CommandName New-GraphBulkRequest -MockWith {
            foreach ($Request in $Requests) {
                $TenantId = switch ($Request.id) { 'fabrikam.com' { $script:TenantA } 'tailspin.com' { $script:TenantB } default { $null } }
                if ($TenantId) { [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ tenantId = $TenantId } } }
                else { [pscustomobject]@{ id = $Request.id; status = 404; body = $null } }
            }
        }
    }

    It 'treats the legacy GuestsOrExternalUsers include token as every guest category' {
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{ includeUsers = @('GuestsOrExternalUsers') })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-intguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-extmember'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-member'].CoveredByCA | Should -Be 'Not Enforced'
        $Result['u-b2bguest'].CAPolicies[0].DisplayName | Should -Be 'Guest MFA'
    }

    It 'matches guestOrExternalUserTypes against the user category and trims spaces' {
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeGuestsOrExternalUsers = [pscustomobject]@{ guestOrExternalUserTypes = 'b2bCollaborationGuest, internalGuest'; externalTenants = [pscustomobject]@{ membershipKind = 'all' } }
            })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-intguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-extmember'].CoveredByCA | Should -Be 'Not Enforced'
        $Result['u-member'].CoveredByCA | Should -Be 'Not Enforced'
    }

    It 'covers #EXT# members when b2bCollaborationMember is targeted' {
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeGuestsOrExternalUsers = [pscustomobject]@{ guestOrExternalUserTypes = 'b2bCollaborationMember'; externalTenants = $null }
            })

        $Result['u-extmember'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Not Enforced'
        $Result['u-intguest'].CoveredByCA | Should -Be 'Not Enforced'
    }

    It 'honours enumerated externalTenants by resolving the external UPN domain to a tenant' {
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeGuestsOrExternalUsers = [pscustomobject]@{
                    guestOrExternalUserTypes = 'b2bCollaborationGuest,b2bCollaborationMember'
                    externalTenants          = [pscustomobject]@{ membershipKind = 'enumerated'; members = @($script:TenantA) }
                }
            })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-extmember'].CoveredByCA | Should -Be 'Not Enforced'
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            @($Requests.id) -contains 'fabrikam.com' -and @($Requests.id) -contains 'tailspin.com' -and @($Requests).Count -eq 2
        }
    }

    It 'only excludes guests from the enumerated tenant on an All users policy' {
        # Shape seen in real tenants: exclude the partner tenant's B2B guests from the All-users MFA policy.
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeUsers                 = @('All')
                excludeGuestsOrExternalUsers = [pscustomobject]@{
                    guestOrExternalUserTypes = 'b2bCollaborationGuest,serviceProvider'
                    externalTenants          = [pscustomobject]@{ membershipKind = 'enumerated'; members = @($script:TenantB) }
                }
            })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-extmember'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-member'].CoveredByCA | Should -Be 'Enforced - All Apps'
    }

    It 'reports Unknown instead of a verdict when the tenant lookup fails' {
        Mock -CommandName New-GraphBulkRequest -MockWith { throw 'Graph 429' }
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeUsers                 = @('All')
                excludeGuestsOrExternalUsers = [pscustomobject]@{ guestOrExternalUserTypes = 'b2bCollaborationGuest'; externalTenants = [pscustomobject]@{ membershipKind = 'enumerated'; members = @($script:TenantB) } }
            })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Unknown - external tenant lookup failed'
        $Result['u-b2bguest'].CAPolicies[0].UserIncluded | Should -BeNullOrEmpty
        $Result['u-extmember'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-member'].CoveredByCA | Should -Be 'Enforced - All Apps'
    }

    It 'treats a per-domain 404 as no home tenant rather than unknown' {
        Mock -CommandName New-GraphBulkRequest -MockWith { foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = 404; body = $null } } }
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeUsers                 = @('All')
                excludeGuestsOrExternalUsers = [pscustomobject]@{ guestOrExternalUserTypes = 'b2bCollaborationGuest'; externalTenants = [pscustomobject]@{ membershipKind = 'enumerated'; members = @($script:TenantB) } }
            })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-b2bguest'].CAPolicies[0].UserIncluded | Should -BeTrue
    }

    It 'keeps a definite verdict when another policy covers the user' {
        Mock -CommandName New-GraphBulkRequest -MockWith { foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = 429; body = $null } } }
        $Policies = @(
            (New-TestPolicy -Users @{
                    includeUsers                 = @('All')
                    excludeGuestsOrExternalUsers = [pscustomobject]@{ guestOrExternalUserTypes = 'b2bCollaborationGuest'; externalTenants = [pscustomobject]@{ membershipKind = 'enumerated'; members = @($script:TenantB) } }
                })
            (New-TestPolicy -Users @{ includeUsers = @('GuestsOrExternalUsers') })
        )
        $Result = Get-TestMFAState -Policy $Policies

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
    }

    It 'skips the tenant lookup when no policy enumerates external tenants for a B2B type' {
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeUsers                 = @('All')
                excludeGuestsOrExternalUsers = [pscustomobject]@{ guestOrExternalUserTypes = 'serviceProvider'; externalTenants = [pscustomobject]@{ membershipKind = 'enumerated'; members = @($script:TenantA) } }
            })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
    }

    It 'excludes guests from an All users policy via excludeGuestsOrExternalUsers' {
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeUsers                 = @('All')
                excludeGuestsOrExternalUsers = [pscustomobject]@{ guestOrExternalUserTypes = 'b2bCollaborationGuest'; externalTenants = [pscustomobject]@{ membershipKind = 'all' } }
            })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Not Enforced'
        $Result['u-b2bguest'].CAPolicies[0].UserIncluded | Should -BeFalse
        $Result['u-intguest'].CoveredByCA | Should -Be 'Enforced - All Apps'
        $Result['u-member'].CoveredByCA | Should -Be 'Enforced - All Apps'
    }

    It 'honours the legacy GuestsOrExternalUsers exclude token' {
        $Result = Get-TestMFAState -Policy (New-TestPolicy -Users @{
                includeUsers = @('All')
                excludeUsers = @('GuestsOrExternalUsers')
            })

        $Result['u-b2bguest'].CoveredByCA | Should -Be 'Not Enforced'
        $Result['u-intguest'].CoveredByCA | Should -Be 'Not Enforced'
        $Result['u-extmember'].CoveredByCA | Should -Be 'Not Enforced'
        $Result['u-member'].CoveredByCA | Should -Be 'Enforced - All Apps'
    }
}

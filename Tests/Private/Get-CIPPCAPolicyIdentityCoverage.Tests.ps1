# Pester tests for Get-CIPPCAPolicyIdentityCoverage — identity assignment who/why resolution.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPCAPolicyIdentityCoverage.ps1')

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $ErrorAction, $noPagination, $ComplexFilter) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $Version) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $AsApp, $type) }

    $script:UserA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:UserB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    $script:UserC = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    $script:UserX = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    $script:GroupStaff = '11111111-1111-1111-1111-111111111111'
    $script:GroupBreak = '22222222-2222-2222-2222-222222222222'
    $script:GroupAdmins = '33333333-3333-3333-3333-333333333333'
    $script:RoleGa = '62e90394-69f5-4237-9190-012177145e10'
    $script:RoleGaDef = '62e90394-69f5-4237-9190-012177145e10'
}

Describe 'Get-CIPPCAPolicyIdentityCoverage' {
    BeforeEach {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ id = $script:UserA; displayName = 'Alice'; userPrincipalName = 'alice@contoso.com'; userType = 'Member' }
                    [pscustomobject]@{ id = $script:UserB; displayName = 'Bob'; userPrincipalName = 'bob@contoso.com'; userType = 'Member' }
                    [pscustomobject]@{ id = $script:UserC; displayName = 'Carol'; userPrincipalName = 'carol@contoso.com'; userType = 'Member' }
                )
            }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
    }

    It 'returns only touched users (untouched directory user absent)' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-1'
                displayName = 'Include Alice'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @($script:UserA)
                        excludeUsers  = @()
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-1'

        $Result.identities.id | Should -Contain $script:UserA
        $Result.identities.id | Should -Not -Contain $script:UserX
        $Result.summary.touchedCount | Should -Be 1
        $Result.identities[0].status | Should -Be 'covered'
        $Result.identities[0].includeReasons[0].value | Should -Be "includeUsers:$($script:UserA)"
    }

    It 'keeps exclude-only users with status excluded' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-2'
                displayName = 'Exclude only Bob'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @('None')
                        excludeUsers  = @($script:UserB)
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-2'

        $Result.identities.Count | Should -Be 1
        $Result.identities[0].id | Should -Be $script:UserB
        $Result.identities[0].status | Should -Be 'excluded'
        $Result.identities[0].includeReasons.Count | Should -Be 0
        $Result.identities[0].excludeReasons[0].type | Should -Be 'excludeUsers'
    }

    It 'sets includesAllUsers without emitting every directory user' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-3'
                displayName = 'All users'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @('All')
                        excludeUsers  = @()
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-3'

        $Result.includesAllUsers | Should -BeTrue
        $Result.hasExclusions | Should -BeFalse
        $Result.identities.Count | Should -Be 0
        $Result.summary.touchedCount | Should -Be 0
    }

    It 'All + exclude user yields excluded row with All include reason' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-4'
                displayName = 'All minus Alice'
                state       = 'enabledForReportingButNotEnforced'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @('All')
                        excludeUsers  = @($script:UserA)
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-4'

        $Result.includesAllUsers | Should -BeTrue
        $Result.hasExclusions | Should -BeTrue
        $Result.identities.Count | Should -Be 1
        $Result.identities[0].status | Should -Be 'excluded'
        $Result.identities[0].includeReasons.value | Should -Contain 'includeUsers:All'
        $Result.identities[0].excludeReasons.type | Should -Contain 'excludeUsers'
        $Result.state | Should -Be 'enabledForReportingButNotEnforced'
    }

    It 'include+exclude yields status excluded with both reason arrays' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-5'
                displayName = 'Alice included and excluded'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @($script:UserA)
                        excludeUsers  = @($script:UserA)
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-5'
        $Row = $Result.identities | Where-Object { $_.id -eq $script:UserA }

        $Row.status | Should -Be 'excluded'
        $Row.includeReasons.Count | Should -BeGreaterThan 0
        $Row.excludeReasons.Count | Should -BeGreaterThan 0
    }

    It 'expands include groups transitively and attributes multi-path reasons' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-6'
                displayName = 'Group and role'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @($script:UserA)
                        excludeUsers  = @()
                        includeGroups = @($script:GroupStaff)
                        excludeGroups = @()
                        includeRoles  = @($script:RoleGa)
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ id = $script:RoleGaDef; templateId = $script:RoleGa; displayName = 'Global Administrator' }
            )
        } -ParameterFilter { $uri -like '*/roleDefinitions*' }

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{
                    principalId      = $script:UserA
                    roleDefinitionId = $script:RoleGaDef
                    principal        = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = $script:UserA }
                }
            )
        } -ParameterFilter { $uri -like '*/roleAssignments*' }

        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp, $Version)
            $Out = [System.Collections.Generic.List[object]]::new()
            foreach ($Req in $Requests) {
                if ($Req.id -like 'details-*') {
                    $Out.Add([pscustomobject]@{
                            id     = $Req.id
                            status = 200
                            body   = [pscustomobject]@{ id = $script:GroupStaff; displayName = 'All Staff' }
                        })
                } elseif ($Req.id -like 'transitive-*') {
                    $Out.Add([pscustomobject]@{
                            id     = $Req.id
                            status = 200
                            body   = [pscustomobject]@{
                                value = @(
                                    [pscustomobject]@{ id = $script:UserA }
                                    [pscustomobject]@{ id = $script:UserB }
                                )
                            }
                        })
                } elseif ($Req.id -like 'direct-*') {
                    # Alice is a direct member; Bob is only nested.
                    $Out.Add([pscustomobject]@{
                            id     = $Req.id
                            status = 200
                            body   = [pscustomobject]@{
                                value = @(
                                    [pscustomobject]@{ id = $script:UserA }
                                )
                            }
                        })
                }
            }
            return @($Out)
        }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-6'
        $Alice = $Result.identities | Where-Object { $_.id -eq $script:UserA }
        $Bob = $Result.identities | Where-Object { $_.id -eq $script:UserB }

        $Alice | Should -Not -BeNullOrEmpty
        $Alice.status | Should -Be 'covered'
        $Alice.includeReasons.Count | Should -BeGreaterOrEqual 3
        ($Alice.includeReasons | Where-Object { $_.type -eq 'includeUsers' }).Count | Should -Be 1
        ($Alice.includeReasons | Where-Object { $_.type -eq 'includeGroups' }).Count | Should -Be 1
        ($Alice.includeReasons | Where-Object { $_.type -eq 'includeRoles' }).Count | Should -Be 1
        $AliceGroup = $Alice.includeReasons | Where-Object { $_.type -eq 'includeGroups' } | Select-Object -First 1
        $AliceGroup.label | Should -Be 'Group: All Staff'
        $AliceGroup.transitive | Should -BeFalse

        $Bob.status | Should -Be 'covered'
        $BobGroup = $Bob.includeReasons | Where-Object { $_.type -eq 'includeGroups' } | Select-Object -First 1
        $BobGroup.label | Should -Be 'Group: All Staff (nested)'
        $BobGroup.transitive | Should -BeTrue
        $Result.identities.id | Should -Not -Contain $script:UserC
    }

    It 'records unresolved deleted group GUIDs' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-7'
                displayName = 'Missing group'
                state       = 'disabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @()
                        excludeUsers  = @()
                        includeGroups = @($script:GroupBreak)
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        Mock -CommandName New-GraphBulkRequest -MockWith {
            @(
                [pscustomobject]@{
                    id     = "details-$($script:GroupBreak)"
                    status = 404
                    body   = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Not Found' } }
                }
                [pscustomobject]@{
                    id     = "transitive-$($script:GroupBreak)"
                    status = 404
                    body   = $null
                }
                [pscustomobject]@{
                    id     = "direct-$($script:GroupBreak)"
                    status = 404
                    body   = $null
                }
            )
        }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-7'

        $Result.unresolved.Count | Should -BeGreaterThan 0
        $Result.unresolved[0].field | Should -Be 'includeGroups'
        $Result.unresolved[0].id | Should -Be $script:GroupBreak
        $Result.state | Should -Be 'disabled'
    }

    It 'expands GuestsOrExternalUsers token to guest users only' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-8'
                displayName = 'Guests'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @('GuestsOrExternalUsers')
                        excludeUsers  = @()
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ id = $script:UserC; displayName = 'Guest Carol'; userPrincipalName = 'carol_ext#EXT#@contoso.com'; userType = 'Guest' }
            )
        } -ParameterFilter { $uri -like "*/users?*userType eq 'Guest'*" -or $uri -like '*userType%20eq%20%27Guest%27*' }

        # Fallback: match any users query for guests
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ id = $script:UserC; displayName = 'Guest Carol'; userPrincipalName = 'carol_ext#EXT#@contoso.com'; userType = 'Guest' }
            )
        } -ParameterFilter { $uri -like '*/users?*' }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-8'

        $Result.identities.id | Should -Contain $script:UserC
        $Result.identities[0].includeReasons.value | Should -Contain 'includeUsers:GuestsOrExternalUsers'
        $Result.identities.id | Should -Not -Contain $script:UserA
    }

    It 'expands group-held role assignments to transitive user members' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-9'
                displayName = 'Admin MFA'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @()
                        excludeUsers  = @()
                        includeGroups = @()
                        excludeGroups = @()
                        includeRoles  = @($script:RoleGa)
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ id = $script:RoleGaDef; templateId = $script:RoleGa; displayName = 'Global Administrator' }
            )
        } -ParameterFilter { $uri -like '*/roleDefinitions*' }

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{
                    principalId      = $script:GroupAdmins
                    roleDefinitionId = $script:RoleGaDef
                    principal        = [pscustomobject]@{
                        '@odata.type' = '#microsoft.graph.group'
                        id            = $script:GroupAdmins
                        displayName   = 'Role Admins'
                    }
                }
            )
        } -ParameterFilter { $uri -like '*/roleAssignments*' }

        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp, $Version)
            @(
                [pscustomobject]@{
                    id     = "roleGroup-$($script:GroupAdmins)"
                    status = 200
                    body   = [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{ id = $script:UserB }
                            [pscustomobject]@{ id = $script:UserC }
                        )
                    }
                }
            )
        }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-9'
        $Bob = $Result.identities | Where-Object { $_.id -eq $script:UserB }
        $Carol = $Result.identities | Where-Object { $_.id -eq $script:UserC }

        $Result.identities.id | Should -Not -Contain $script:UserA
        $Bob.status | Should -Be 'covered'
        $Bob.includeReasons[0].label | Should -Be 'Role: Global Administrator via group Role Admins'
        $Bob.includeReasons[0].viaGroupId | Should -Be $script:GroupAdmins
        $Carol.status | Should -Be 'covered'
        $Carol.includeReasons[0].type | Should -Be 'includeRoles'
    }

    It 'filters guest blocks by guestOrExternalUserTypes and externalTenants' {
        $ExternalTenant = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $OtherTenant = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'

        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-10'
                displayName = 'B2B guests from one tenant'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers                 = @()
                        excludeUsers                 = @()
                        includeGroups                = @()
                        excludeGroups                = @()
                        includeRoles                 = @()
                        excludeRoles                 = @()
                        includeGuestsOrExternalUsers = [pscustomobject]@{
                            guestOrExternalUserTypes = 'b2bCollaborationGuest'
                            externalTenants          = [pscustomobject]@{
                                membershipKind = 'enumerated'
                                members        = @($ExternalTenant)
                            }
                        }
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{
                    id                = $script:UserA
                    displayName       = 'Matching B2B guest'
                    userPrincipalName = 'a_fabrikam.com#EXT#@contoso.com'
                    userType          = 'Guest'
                    identities        = @(
                        [pscustomobject]@{ signInType = 'federated'; issuer = $ExternalTenant }
                    )
                }
                [pscustomobject]@{
                    id                = $script:UserB
                    displayName       = 'Wrong-tenant B2B guest'
                    userPrincipalName = 'b_other.com#EXT#@contoso.com'
                    userType          = 'Guest'
                    identities        = @(
                        [pscustomobject]@{ signInType = 'federated'; issuer = $OtherTenant }
                    )
                }
                [pscustomobject]@{
                    id                = $script:UserC
                    displayName       = 'Internal guest'
                    userPrincipalName = 'carol@contoso.com'
                    userType          = 'Guest'
                    identities        = @()
                }
            )
        } -ParameterFilter { $uri -like "*/users?*userType eq 'Guest'*" -or $uri -like '*userType%20eq%20%27Guest%27*' -or ($uri -like '*/users?*' -and $uri -like '*Guest*') }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-10'

        $Result.identities.id | Should -Contain $script:UserA
        $Result.identities.id | Should -Not -Contain $script:UserB
        $Result.identities.id | Should -Not -Contain $script:UserC
        $Result.identities[0].includeReasons[0].type | Should -Be 'includeGuestsOrExternalUsers'
    }

    It 'records unresolved when group member expansion throws' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-11'
                displayName = 'Group expand fail'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers  = @()
                        excludeUsers  = @()
                        includeGroups = @($script:GroupStaff)
                        excludeGroups = @()
                        includeRoles  = @()
                        excludeRoles  = @()
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp, $Version)
            $HasMembers = @($Requests | Where-Object { $_.id -like 'transitive-*' -or $_.id -like 'direct-*' }).Count -gt 0
            if ($HasMembers) {
                throw 'Graph bulk failure'
            }
            @(
                [pscustomobject]@{
                    id     = "details-$($script:GroupStaff)"
                    status = 200
                    body   = [pscustomobject]@{ id = $script:GroupStaff; displayName = 'All Staff' }
                }
            )
        }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-11'

        $Result.identities.Count | Should -Be 0
        $Result.unresolved.Count | Should -BeGreaterThan 0
        $Result.unresolved[0].field | Should -Be 'includeGroups'
        $Result.unresolved[0].id | Should -Be $script:GroupStaff
        $Result.unresolved[0].error | Should -Match 'Group member expansion failed'
    }

    It 'does not dump all guests for non-enumerable guest types' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-12'
                displayName = 'Service provider only'
                state       = 'enabled'
                conditions  = [pscustomobject]@{
                    users = [pscustomobject]@{
                        includeUsers                 = @()
                        excludeUsers                 = @()
                        includeGroups                = @()
                        excludeGroups                = @()
                        includeRoles                 = @()
                        excludeRoles                 = @()
                        includeGuestsOrExternalUsers = [pscustomobject]@{
                            guestOrExternalUserTypes = 'serviceProvider'
                            externalTenants          = [pscustomobject]@{ membershipKind = 'all' }
                        }
                    }
                }
            }
        } -ParameterFilter { $uri -like '*/conditionalAccess/policies/*' }

        Mock -CommandName New-GraphGetRequest -MockWith {
            throw 'Should not enumerate directory guests for serviceProvider-only policies'
        } -ParameterFilter { $uri -like '*/users?*' }

        $Result = Get-CIPPCAPolicyIdentityCoverage -TenantFilter 'contoso.com' -PolicyId 'policy-12'

        $Result.identities.Count | Should -Be 0
        $Result.unresolved | Where-Object { $_.id -eq 'serviceProvider' } | Should -Not -BeNullOrEmpty
    }
}

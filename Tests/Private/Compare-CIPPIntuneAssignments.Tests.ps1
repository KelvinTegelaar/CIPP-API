# Pester tests for Compare-CIPPIntuneAssignments
#
# The failure this guards is a drift deviation that never clears: the check asserted an exact set of
# assignments while remediation only ever appended to them, and asserted "no include targets" for
# every AssignTo value it did not recognise (including unset and 'Do not assign'). Both produce a
# policy that is correctly assigned in the portal and permanently non-compliant in CIPP.
#
# So the rule these tests encode is: the verdict may only assert what remediation manages. Anything
# else belongs in the reported detail, not in the boolean.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Minimal stub so Mock has a command to replace
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $ComplexFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignmentTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneAssignments.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:SalesId = '11111111-1111-1111-1111-111111111111'
    $script:PilotId = '22222222-2222-2222-2222-222222222222'
    $script:ContractorsId = '33333333-3333-3333-3333-333333333333'
    $script:FilterId = '44444444-4444-4444-4444-444444444444'

    function New-GroupAssignment {
        param($GroupId, $FilterId, $FilterType)
        $Target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $GroupId }
        if ($FilterId) {
            $Target['deviceAndAppManagementAssignmentFilterId'] = $FilterId
            $Target['deviceAndAppManagementAssignmentFilterType'] = $FilterType
        }
        [PSCustomObject]@{ target = [PSCustomObject]$Target }
    }

    function New-ExclusionAssignment {
        param($GroupId)
        [PSCustomObject]@{
            target = [PSCustomObject]@{
                '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'
                groupId       = $GroupId
            }
        }
    }

    function New-BroadAssignment {
        param($ODataType, $FilterId, $FilterType)
        $Target = @{ '@odata.type' = $ODataType }
        if ($FilterId) {
            $Target['deviceAndAppManagementAssignmentFilterId'] = $FilterId
            $Target['deviceAndAppManagementAssignmentFilterType'] = $FilterType
        }
        [PSCustomObject]@{ target = [PSCustomObject]$Target }
    }
}

Describe 'Compare-CIPPIntuneAssignments' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } -MockWith {
            @(
                [PSCustomObject]@{ id = $script:SalesId; displayName = 'Sales Users' }
                [PSCustomObject]@{ id = $script:PilotId; displayName = 'Pilot Users' }
                [PSCustomObject]@{ id = $script:ContractorsId; displayName = 'Contractors' }
            )
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*assignmentFilters*' } -MockWith {
            @([PSCustomObject]@{ id = $script:FilterId; displayName = 'Corporate iOS' })
        }
    }

    Context 'when the standard names no assignment target' {
        It 'does not assert anything about a policy that is assigned (<Case>)' -ForEach @(
            @{ Case = 'AssignTo unset'; AssignTo = $null }
            @{ Case = 'AssignTo empty'; AssignTo = '' }
            @{ Case = "AssignTo 'Do not assign'"; AssignTo = 'On' }
        ) {
            # Remediation adds no include target for these, so a mismatch here is a deviation that
            # can never be cleared. This is the regression: it used to return $false.
            $Existing = @(
                New-GroupAssignment -GroupId $script:SalesId
                New-BroadAssignment -ODataType '#microsoft.graph.allLicensedUsersAssignmentTarget'
            )

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo $AssignTo -TenantFilter $script:Tenant

            $Result.Matched | Should -BeTrue
            $Result.Reasons | Should -BeNullOrEmpty
        }

        It 'ignores exclusions in the tenant when none are configured' {
            $Existing = @(
                New-GroupAssignment -GroupId $script:SalesId
                New-ExclusionAssignment -GroupId $script:ContractorsId
            )

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'On' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeTrue
        }

        It "still requires configured exclusions under 'Do not assign', which remediation does apply" {
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'On' -ExpectedExcludeGroup 'Contractors' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.MissingExcludeGroups.id | Should -Be $script:ContractorsId
            $Result.Reasons -join '; ' | Should -BeLike '*Contractors*'
        }

        It 'does not assert exclusions when AssignTo is unset, because remediation never runs' {
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo '' -ExpectedExcludeGroup 'Contractors' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeTrue
        }
    }

    Context 'custom group assignment' {
        It 'matches when the policy is assigned to exactly the configured group' {
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeTrue
            $Result.Reasons | Should -BeNullOrEmpty
            $Result.Unknown | Should -BeFalse
        }

        It 'resolves comma-separated names and wildcards the same way Set-CIPPAssignedPolicy does' {
            $Existing = @(
                New-GroupAssignment -GroupId $script:SalesId
                New-GroupAssignment -GroupId $script:PilotId
            )

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users, Pilot*' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeTrue
        }

        It 'names the group that is missing rather than just failing' {
            $Existing = @(New-GroupAssignment -GroupId $script:PilotId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.MissingIncludeGroups.displayName | Should -Be 'Sales Users'
            $Result.ExtraIncludeGroups.displayName | Should -Be 'Pilot Users'
            $Result.Reasons -join '; ' | Should -BeLike '*Sales Users*'
        }

        It 'reports a configured group name that matches nothing in the tenant' {
            # A renamed or deleted group is a common cause of a policy that looks correctly assigned
            # but no longer matches the standard. Silently resolving to no ids made it match.
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Group That Was Renamed' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.UnresolvedGroups | Should -Be 'Group That Was Renamed'
            $Result.Reasons -join '; ' | Should -BeLike '*matches no group*'
        }

        It 'accepts the { label, value } AssignTo shape from older templates' {
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId)
            $AssignTo = [PSCustomObject]@{ label = 'Assign to Custom Group'; value = 'customGroup' }

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo $AssignTo -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant

            $Result.Managed | Should -BeTrue
            $Result.Matched | Should -BeTrue
        }
    }

    Context 'broad targets' {
        It 'matches All Users' {
            $Existing = @(New-BroadAssignment -ODataType '#microsoft.graph.allLicensedUsersAssignmentTarget')

            (Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'allLicensedUsers' -TenantFilter $script:Tenant).Matched |
                Should -BeTrue
        }

        It 'requires both targets for AllDevicesAndUsers' {
            $Existing = @(New-BroadAssignment -ODataType '#microsoft.graph.allDevicesAssignmentTarget')

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'AllDevicesAndUsers' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.Reasons -join '; ' | Should -BeLike '*allLicensedUsersAssignmentTarget*'
        }

        It 'matches when both targets are present' {
            $Existing = @(
                New-BroadAssignment -ODataType '#microsoft.graph.allDevicesAssignmentTarget'
                New-BroadAssignment -ODataType '#microsoft.graph.allLicensedUsersAssignmentTarget'
            )

            (Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'AllDevicesAndUsers' -TenantFilter $script:Tenant).Matched |
                Should -BeTrue
        }

        It 'reports a group assignment that the standard does not expect' {
            $Existing = @(
                New-BroadAssignment -ODataType '#microsoft.graph.allLicensedUsersAssignmentTarget'
                New-GroupAssignment -GroupId $script:PilotId
            )

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'allLicensedUsers' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.ExtraIncludeGroups.displayName | Should -Be 'Pilot Users'
        }

        It 'reports an unexpected broad target' {
            $Existing = @(
                New-GroupAssignment -GroupId $script:SalesId
                New-BroadAssignment -ODataType '#microsoft.graph.allDevicesAssignmentTarget'
            )

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.Reasons -join '; ' | Should -BeLike '*allDevicesAssignmentTarget*'
        }
    }

    Context 'broad targets on an App Protection policy' {
        # Remediation cannot write an allLicensedUsers target here - the MAM service rejects it -
        # so expecting one would be a deviation no run could ever clear.
        BeforeAll {
            $script:AllUsersGroupId = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'
        }

        It 'matches the group assignment remediation actually writes for all users' {
            $Existing = @(New-GroupAssignment -GroupId $script:AllUsersGroupId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'allLicensedUsers' -PolicyType 'AppProtection' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeTrue
            $Result.ExtraIncludeGroups | Should -BeNullOrEmpty
        }

        It 'reports the virtual group by name when it is missing' {
            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments @() -ExpectedAssignTo 'allLicensedUsers' -PolicyType 'AppProtection' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.MissingIncludeGroups.displayName | Should -Be 'All Users'
            $Result.Reasons -join '; ' | Should -Not -BeLike "*$script:AllUsersGroupId*"
        }

        It 'does not demand an allLicensedUsers target that cannot be written' {
            $Existing = @(New-GroupAssignment -GroupId $script:AllUsersGroupId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'allLicensedUsers' -PolicyType 'iosManagedAppProtections' -TenantFilter $script:Tenant

            $Result.Reasons -join '; ' | Should -Not -BeLike '*allLicensedUsersAssignmentTarget*'
        }

        It 'expects only the users half of AllDevicesAndUsers, matching what remediation applies' {
            $Existing = @(New-GroupAssignment -GroupId $script:AllUsersGroupId)

            (Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'AllDevicesAndUsers' -PolicyType 'AppProtection' -TenantFilter $script:Tenant).Matched |
                Should -BeTrue
        }

        It 'still reports a group the standard does not expect' {
            $Existing = @(
                New-GroupAssignment -GroupId $script:AllUsersGroupId
                New-GroupAssignment -GroupId $script:PilotId
            )

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'allLicensedUsers' -PolicyType 'AppProtection' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.ExtraIncludeGroups.displayName | Should -Be 'Pilot Users'
        }
    }

    Context 'exclusion groups' {
        It 'matches when the configured exclusion is present' {
            $Existing = @(
                New-GroupAssignment -GroupId $script:SalesId
                New-ExclusionAssignment -GroupId $script:ContractorsId
            )

            (Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -ExpectedExcludeGroup 'Contractors' -TenantFilter $script:Tenant).Matched |
                Should -BeTrue
        }

        It 'reports an exclusion the standard does not define when it owns the assignment' {
            $Existing = @(
                New-GroupAssignment -GroupId $script:SalesId
                New-ExclusionAssignment -GroupId $script:PilotId
            )

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.ExtraExcludeGroups.displayName | Should -Be 'Pilot Users'
        }
    }

    Context 'assignment filters' {
        It 'matches when the filter is on every include target in the expected mode' {
            $Existing = @(
                New-GroupAssignment -GroupId $script:SalesId -FilterId $script:FilterId -FilterType 'include'
                New-ExclusionAssignment -GroupId $script:ContractorsId
            )

            (Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -ExpectedExcludeGroup 'Contractors' -ExpectedAssignmentFilter 'Corporate iOS' -ExpectedAssignmentFilterType 'include' -TenantFilter $script:Tenant).Matched |
                Should -BeTrue
        }

        It 'reports a filter applied to only some of the include targets' {
            # Remediation stamps the filter onto every include target, so a partial application is a
            # real difference rather than a pass.
            $Existing = @(
                New-GroupAssignment -GroupId $script:SalesId -FilterId $script:FilterId -FilterType 'include'
                New-GroupAssignment -GroupId $script:PilotId
            )

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users, Pilot Users' -ExpectedAssignmentFilter 'Corporate iOS' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.Reasons -join '; ' | Should -BeLike '*not applied to every assignment target*'
        }

        It 'reports the wrong filter mode' {
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId -FilterId $script:FilterId -FilterType 'include')

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -ExpectedAssignmentFilter 'Corporate iOS' -ExpectedAssignmentFilterType 'exclude' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.Reasons -join '; ' | Should -BeLike "*'exclude' mode*"
        }

        It 'reports a filter that does not exist in the tenant' {
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -ExpectedAssignmentFilter 'No Such Filter' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.Reasons -join '; ' | Should -BeLike '*does not exist in this tenant*'
        }

        It 'reports a filter present in the tenant that the standard does not specify' {
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId -FilterId $script:FilterId -FilterType 'include')

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.Reasons -join '; ' | Should -BeLike '*does not specify one*'
        }

        It 'treats the empty GUID as no filter' {
            # Graph returns all-zeros rather than null on some assignment shapes; reading that as a
            # filter would fail every unfiltered policy.
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId -FilterId '00000000-0000-0000-0000-000000000000' -FilterType 'none')

            (Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant).Matched |
                Should -BeTrue
        }
    }

    Context 'unreadable assignments' {
        It 'returns unknown rather than a mismatch when Graph fails' {
            # $false here would write a drift entry that survives every later run and points at a
            # policy that was never wrong.
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } -MockWith {
                throw 'Request throttled'
            }
            $Existing = @(New-GroupAssignment -GroupId $script:SalesId)

            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments $Existing -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant -WarningAction SilentlyContinue

            $Result.Unknown | Should -BeTrue
            $Result.Matched | Should -BeNullOrEmpty
            $Result.Error | Should -Be 'Request throttled'
        }
    }

    Context 'policy with no assignments at all' {
        It 'reports the expected group as missing' {
            $Result = Compare-CIPPIntuneAssignments -ExistingAssignments @() -ExpectedAssignTo 'customGroup' -ExpectedCustomGroup 'Sales Users' -TenantFilter $script:Tenant

            $Result.Matched | Should -BeFalse
            $Result.MissingIncludeGroups.displayName | Should -Be 'Sales Users'
        }

        It 'matches when the standard names no target' {
            (Compare-CIPPIntuneAssignments -ExistingAssignments @() -ExpectedAssignTo $null -TenantFilter $script:Tenant).Matched |
                Should -BeTrue
        }
    }
}

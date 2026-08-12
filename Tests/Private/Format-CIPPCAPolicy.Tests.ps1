# Pester tests for Format-CIPPCAPolicy
# Deploying a CA template over an existing policy is a PATCH, and PATCH merges - so what the body
# says (and what it omits) decides whether tenant-side deviations are cleared or silently survive.
# These pin the canonicalizer's two phases: absent managed keys are expanded back as their cleared
# form ([] / null), and only the containers Graph rejects when empty collapse to null. Empty
# assignment arrays always survive into the body - they are the only thing that clears one.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPCAPolicy.ps1')

    function Convert-Policy ($Json) {
        $Object = $Json | ConvertFrom-Json
        Format-CIPPCAPolicy -Policy $Object
        return $Object
    }
}

Describe 'Format-CIPPCAPolicy' {

    Context 'stored templates stripped by older editors are healed (expansion)' {
        BeforeAll {
            # The shape an old-editor template actually has at rest: every emptied key was
            # stripped at save time, so only populated assignments remain.
            $script:Healed = Convert-Policy '{
                "displayName": "CA201",
                "conditions": {
                    "clientAppTypes": ["all"],
                    "applications": { "includeApplications": ["All"] },
                    "users": { "includeUsers": ["All"], "excludeGroups": ["Break Glass"] }
                },
                "grantControls": { "operator": "OR", "builtInControls": ["mfa"] }
            }'
        }

        It 'restores absent user collection <Property> as an empty array' -ForEach @(
            @{ Property = 'excludeUsers' }
            @{ Property = 'includeGroups' }
            @{ Property = 'includeRoles' }
            @{ Property = 'excludeRoles' }
        ) {
            $Users = $script:Healed.conditions.users
            $Users.PSObject.Properties.Name | Should -Contain $Property
            @($Users.$Property).Count | Should -Be 0
            # An empty array piped into Should reads as null, so compare without the pipeline.
            ($null -eq $Users.$Property) | Should -BeFalse
        }

        It 'restores absent condition block <Block> as null' -ForEach @(
            @{ Block = 'platforms' }
            @{ Block = 'locations' }
            @{ Block = 'devices' }
            @{ Block = 'clientApplications' }
            @{ Block = 'authenticationFlows' }
            @{ Block = 'insiderRiskLevels' }
        ) {
            $script:Healed.conditions.PSObject.Properties.Name | Should -Contain $Block
            $script:Healed.conditions.$Block | Should -BeNullOrEmpty
        }

        It 'restores absent guest blocks as null' {
            $Users = $script:Healed.conditions.users
            $Users.PSObject.Properties.Name | Should -Contain 'includeGuestsOrExternalUsers'
            $Users.PSObject.Properties.Name | Should -Contain 'excludeGuestsOrExternalUsers'
            $Users.includeGuestsOrExternalUsers | Should -BeNullOrEmpty
            $Users.excludeGuestsOrExternalUsers | Should -BeNullOrEmpty
        }

        It 'restores absent application collections and filter' {
            $Apps = $script:Healed.conditions.applications
            @($Apps.excludeApplications).Count | Should -Be 0
            @($Apps.includeUserActions).Count | Should -Be 0
            $Apps.PSObject.Properties.Name | Should -Contain 'applicationFilter'
            $Apps.applicationFilter | Should -BeNullOrEmpty
        }

        It 'restores absent risk level collections as empty arrays' {
            @($script:Healed.conditions.signInRiskLevels).Count | Should -Be 0
            @($script:Healed.conditions.userRiskLevels).Count | Should -Be 0
        }

        It 'adds sessionControls as null when grantControls carries the policy' {
            $script:Healed.PSObject.Properties.Name | Should -Contain 'sessionControls'
            $script:Healed.sessionControls | Should -BeNullOrEmpty
        }

        It 'serialises the healed clears into the request body' {
            $Body = ConvertTo-Json -InputObject $script:Healed -Depth 10 -Compress
            $Body | Should -Match '"excludeUsers":\[\]'
            $Body | Should -Match '"platforms":null'
        }

        It 'leaves clientAppTypes alone - Graph requires it non-empty, absence stays a merge' {
            $Policy = Convert-Policy '{
                "displayName": "CA201",
                "conditions": { "users": { "includeUsers": ["All"] } }
            }'
            $Policy.conditions.PSObject.Properties.Name | Should -Not -Contain 'clientAppTypes'
        }

        It 'leaves populated assignments untouched' {
            $script:Healed.conditions.users.includeUsers | Should -Be @('All')
            $script:Healed.conditions.users.excludeGroups | Should -Be @('Break Glass')
            $script:Healed.grantControls.builtInControls | Should -Be @('mfa')
        }
    }

    Context 'grantControls/sessionControls at-least-one rule' {
        It 'adds grantControls as null when only sessionControls carries the policy' {
            $Policy = Convert-Policy '{
                "displayName": "CA201",
                "conditions": { "users": { "includeUsers": ["All"] } },
                "sessionControls": { "signInFrequency": { "isEnabled": true, "type": "hours", "value": 4 } }
            }'
            $Policy.PSObject.Properties.Name | Should -Contain 'grantControls'
            $Policy.grantControls | Should -BeNullOrEmpty
        }

        It 'adds neither when both are absent' {
            $Policy = Convert-Policy '{"displayName":"CA201","conditions":{"users":{"includeUsers":["All"]}}}'
            $Policy.PSObject.Properties.Name | Should -Not -Contain 'sessionControls'
        }

        It 'does not add the counterpart of an explicitly null control' {
            $Policy = Convert-Policy '{"displayName":"CA201","conditions":{"users":{"includeUsers":["All"]}},"grantControls":null}'
            $Policy.PSObject.Properties.Name | Should -Not -Contain 'sessionControls'
        }
    }

    Context 'required parents are never invented' {
        It 'does not invent conditions' {
            $Policy = Convert-Policy '{"displayName":"CA201"}'
            $Policy.PSObject.Properties.Name | Should -Not -Contain 'conditions'
        }

        It 'does not invent users or applications under conditions' {
            $Policy = Convert-Policy '{"displayName":"CA201","conditions":{"clientAppTypes":["all"]}}'
            $Policy.conditions.PSObject.Properties.Name | Should -Not -Contain 'users'
            $Policy.conditions.PSObject.Properties.Name | Should -Not -Contain 'applications'
        }
    }

    Context 'whitespace-only entries normalise to a clean clear' {
        It 'turns a whitespace-only user collection into an empty array' {
            $Policy = Convert-Policy '{
                "displayName": "CA201",
                "conditions": { "users": { "includeUsers": ["All"], "excludeUsers": ["  ", ""] } }
            }'
            @($Policy.conditions.users.excludeUsers).Count | Should -Be 0
        }
    }

    Context 'empty assignments survive so a PATCH can clear them' {
        BeforeAll {
            $script:Policy = Convert-Policy '{
                "displayName": "CA201",
                "conditions": {
                    "userRiskLevels": [],
                    "signInRiskLevels": [],
                    "applications": { "includeApplications": ["All"], "excludeApplications": [] },
                    "users": {
                        "includeUsers": ["All"],
                        "excludeUsers": [],
                        "includeGroups": [],
                        "excludeGroups": ["Break Glass"],
                        "includeRoles": [],
                        "excludeRoles": []
                    }
                },
                "grantControls": { "operator": "OR", "builtInControls": ["mfa"], "termsOfUse": [] }
            }'
        }

        It 'keeps <Property> as an empty array' -ForEach @(
            @{ Property = 'includeGroups' }
            @{ Property = 'excludeUsers' }
            @{ Property = 'includeRoles' }
            @{ Property = 'excludeRoles' }
        ) {
            $Users = $script:Policy.conditions.users
            $Users.PSObject.Properties.Name | Should -Contain $Property
            @($Users.$Property).Count | Should -Be 0
        }

        It 'serialises the empty assignment into the request body' {
            $Body = ConvertTo-Json -InputObject $script:Policy -Depth 10 -Compress
            $Body | Should -Match '"includeGroups":\[\]'
            $Body | Should -Match '"excludeApplications":\[\]'
        }

        It 'leaves populated assignments alone' {
            $script:Policy.conditions.users.includeUsers | Should -Be @('All')
            $script:Policy.conditions.users.excludeGroups | Should -Be @('Break Glass')
            $script:Policy.grantControls.builtInControls | Should -Be @('mfa')
        }
    }

    Context 'containers Graph rejects when empty collapse to null' {
        BeforeAll {
            $script:Collapsed = Convert-Policy '{
                "displayName": "CA201",
                "conditions": {
                    "platforms": { "includePlatforms": [], "excludePlatforms": [] },
                    "locations": { "includeLocations": [], "excludeLocations": [] },
                    "devices": { "deviceFilter": null, "includeDevices": [], "excludeDevices": [] },
                    "clientApplications": { "includeServicePrincipals": [], "excludeServicePrincipals": [] },
                    "users": {
                        "includeUsers": ["All"],
                        "excludeGuestsOrExternalUsers": {
                            "guestOrExternalUserTypes": "",
                            "externalTenants": { "@odata.type": "#microsoft.graph.conditionalAccessAllExternalTenants", "membershipKind": "all" }
                        }
                    }
                },
                "grantControls": { "operator": "OR", "builtInControls": [], "customAuthenticationFactors": [], "termsOfUse": [], "authenticationStrength": null },
                "sessionControls": {}
            }'
        }

        It 'nulls <Path> rather than removing the property' -ForEach @(
            @{ Path = 'platforms' }
            @{ Path = 'locations' }
            @{ Path = 'devices' }
            @{ Path = 'clientApplications' }
        ) {
            $script:Collapsed.conditions.PSObject.Properties.Name | Should -Contain $Path
            $script:Collapsed.conditions.$Path | Should -BeNullOrEmpty
        }

        It 'nulls an excludeGuestsOrExternalUsers block that only carries an @odata.type' {
            $script:Collapsed.conditions.users.excludeGuestsOrExternalUsers | Should -BeNullOrEmpty
        }

        It 'nulls grantControls that carry no actual control' {
            $script:Collapsed.grantControls | Should -BeNullOrEmpty
        }

        It 'nulls an empty sessionControls object' {
            $script:Collapsed.PSObject.Properties.Name | Should -Contain 'sessionControls'
            $script:Collapsed.sessionControls | Should -BeNullOrEmpty
        }
    }

    Context 'populated containers are left intact' {
        BeforeAll {
            $script:Kept = Convert-Policy '{
                "displayName": "CA201",
                "conditions": {
                    "platforms": { "includePlatforms": ["android"], "excludePlatforms": [] },
                    "locations": { "includeLocations": ["All"], "excludeLocations": [] },
                    "devices": { "deviceFilter": { "mode": "exclude", "rule": "device.isCompliant -eq True" } },
                    "clientApplications": { "includeServicePrincipals": ["ServicePrincipalsInMyTenant"], "excludeServicePrincipals": [] },
                    "users": {
                        "includeUsers": ["None"],
                        "includeGuestsOrExternalUsers": {
                            "guestOrExternalUserTypes": "b2bCollaborationGuest",
                            "externalTenants": { "@odata.type": "#microsoft.graph.conditionalAccessAllExternalTenants", "membershipKind": "all" }
                        }
                    }
                },
                "grantControls": { "operator": "OR", "builtInControls": [], "customAuthenticationFactors": [], "termsOfUse": [], "authenticationStrength": { "id": "00000000-0000-0000-0000-000000000002" } }
            }'
        }

        It 'keeps a platform condition that names a platform' {
            $script:Kept.conditions.platforms.includePlatforms | Should -Be @('android')
        }

        It 'keeps a device condition that only has a deviceFilter' {
            $script:Kept.conditions.devices.deviceFilter.rule | Should -Be 'device.isCompliant -eq True'
        }

        It 'keeps a location and clientApplications condition' {
            $script:Kept.conditions.locations.includeLocations | Should -Be @('All')
            $script:Kept.conditions.clientApplications.includeServicePrincipals | Should -Be @('ServicePrincipalsInMyTenant')
        }

        It 'keeps a guest block that names a guest type' {
            $script:Kept.conditions.users.includeGuestsOrExternalUsers.guestOrExternalUserTypes | Should -Be 'b2bCollaborationGuest'
        }

        It 'keeps grantControls held up only by an authentication strength' {
            $script:Kept.grantControls.authenticationStrength.id | Should -Be '00000000-0000-0000-0000-000000000002'
        }
    }

    Context 'filters that select nothing' {
        It 'nulls a <Filter> that has a mode but no rule' -ForEach @(
            @{ Filter = 'applicationFilter'; Parent = 'applications' }
            @{ Filter = 'deviceFilter'; Parent = 'devices' }
            @{ Filter = 'servicePrincipalFilter'; Parent = 'clientApplications' }
        ) {
            $Policy = Convert-Policy ('{
                "displayName": "CA201",
                "conditions": {
                    "users": { "includeUsers": ["All"] },
                    "applications": { "includeApplications": ["All"], "applicationFilter": null },
                    "devices": { "deviceFilter": null, "includeDevices": ["fake"] },
                    "clientApplications": { "includeServicePrincipals": ["fake"], "servicePrincipalFilter": null }
                }
            }' -replace "`"$Filter`": null", ('"{0}": {{ "mode": "include", "rule": "" }}' -f $Filter))

            $Policy.conditions.$Parent.$Filter | Should -BeNullOrEmpty
        }

        It 'collapses a devices block whose only content was a ruleless filter' {
            $Policy = Convert-Policy '{
                "displayName": "CA201",
                "conditions": {
                    "users": { "includeUsers": ["All"] },
                    "devices": { "deviceFilter": { "mode": "exclude", "rule": "  " }, "includeDevices": [] }
                }
            }'
            $Policy.conditions.devices | Should -BeNullOrEmpty
        }

        It 'keeps a filter that has a rule' {
            $Policy = Convert-Policy '{
                "displayName": "CA201",
                "conditions": {
                    "users": { "includeUsers": ["All"] },
                    "applications": { "includeApplications": ["All"], "applicationFilter": { "mode": "include", "rule": "application.tag -eq \"x\"" } }
                }
            }'
            $Policy.conditions.applications.applicationFilter.rule | Should -Be 'application.tag -eq "x"'
        }
    }

    Context 'edge cases' {
        It 'does nothing to a policy with no conditions at all' {
            { Convert-Policy '{"displayName":"CA201"}' } | Should -Not -Throw
        }

        It 'leaves an already-null container null' {
            $Policy = Convert-Policy '{"displayName":"CA201","conditions":{"platforms":null,"users":{"includeUsers":["All"]}}}'
            $Policy.conditions.PSObject.Properties.Name | Should -Contain 'platforms'
            $Policy.conditions.platforms | Should -BeNullOrEmpty
        }
    }
}

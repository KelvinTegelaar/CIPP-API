BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Get-CippHttpPermissions { }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/ConvertTo-CippPermissionRules.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CIPPRolePermissions.ps1')

    $script:Universe = @(
        'CIPP.Core.Read'
        'CIPP.Core.ReadWrite'
        'Identity.User.Read'
        'Identity.User.ReadWrite'
        'Identity.Device.Read'
        'Identity.Device.ReadWrite'
        'Exchange.Mailbox.Read'
        'Exchange.Mailbox.ReadWrite'
        'Tenant.Administration.Read'
        'Tenant.Administration.ReadWrite'
    )
}

Describe 'ConvertTo-CippPermissionRules' {
    It 'converts a flat map to sorted concrete includes, dropping None and duplicates' {
        $Permissions = @{
            IdentityUser   = 'Identity.User.ReadWrite'
            IdentityDevice = 'Identity.Device.None'
            CIPPCore       = 'CIPP.Core.Read'
            Duplicate      = 'CIPP.Core.Read'
        } | ConvertTo-Json

        $Rules = ConvertTo-CippPermissionRules -Permissions $Permissions
        $Rules.Include | Should -Be @('CIPP.Core.Read', 'Identity.User.ReadWrite')
        @($Rules.Exclude).Count | Should -Be 0
    }

    It 'returns empty rules for missing or unparsable input' {
        (ConvertTo-CippPermissionRules -Permissions '').Include | Should -HaveCount 0
        (ConvertTo-CippPermissionRules -Permissions 'not-json{{').Include | Should -HaveCount 0
        (ConvertTo-CippPermissionRules -Permissions $null).Include | Should -HaveCount 0
    }
}

Describe 'Get-CIPPRolePermissions' {
    BeforeEach {
        Mock Get-CippHttpPermissions { $script:Universe }
    }

    It 'expands wildcard rules against the universe, exclude wins' {
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{
                RowKey          = 'helpdesk'
                Permissions     = '{}'
                PermissionRules = '{"Include":["Identity.*.Read"],"Exclude":["Identity.Device.*"]}'
            }
        }

        $Result = Get-CIPPRolePermissions -RoleName 'helpdesk'
        $Result.Permissions | Should -Be @('Identity.User.Read')
        $Result.PermissionRules.Include | Should -Be @('Identity.*.Read')
    }

    It 'handles multi-wildcard patterns' {
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{
                RowKey          = 'mailboxes'
                Permissions     = '{}'
                PermissionRules = '{"Include":["*.Mailbox.*"],"Exclude":[]}'
            }
        }

        (Get-CIPPRolePermissions -RoleName 'mailboxes').Permissions |
            Should -Be @('Exchange.Mailbox.Read', 'Exchange.Mailbox.ReadWrite')
    }

    It 'wildcard roles pick up endpoints added to the universe without a re-save' {
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{
                RowKey          = 'readers'
                Permissions     = '{}'
                PermissionRules = '{"Include":["*.Read"],"Exclude":[]}'
            }
        }

        Mock Get-CippHttpPermissions { $script:Universe + 'NewFeature.Thing.Read' }
        (Get-CIPPRolePermissions -RoleName 'readers').Permissions | Should -Contain 'NewFeature.Thing.Read'
    }

    It 'migrated concrete-string roles stay frozen when the universe grows' {
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{
                RowKey          = 'frozen'
                Permissions     = '{}'
                PermissionRules = '{"Include":["Identity.User.Read"],"Exclude":[]}'
            }
        }

        Mock Get-CippHttpPermissions { $script:Universe + 'NewFeature.Thing.Read' }
        (Get-CIPPRolePermissions -RoleName 'frozen').Permissions | Should -Be @('Identity.User.Read')
    }

    It 'grants the real .Read when a role includes a .ReadWrite the universe never declares' {
        # Some objects only ever ship a .Read endpoint (e.g. Endpoint.Device), yet the role
        # builder still offers a .ReadWrite toggle. A role granted that phantom .ReadWrite must
        # still receive the .Read the endpoints actually check, or it loses all access.
        Mock Get-CippHttpPermissions { @('Endpoint.Device.Read', 'Identity.User.Read', 'Identity.User.ReadWrite') }
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{
                RowKey          = 'devicewriter'
                Permissions     = '{}'
                PermissionRules = '{"Include":["Endpoint.Device.ReadWrite"],"Exclude":[]}'
            }
        }

        (Get-CIPPRolePermissions -RoleName 'devicewriter').Permissions | Should -Be @('Endpoint.Device.Read')
    }

    It 'does not let a .Read include grant the .ReadWrite variant' {
        # The implication is one-way. Read must never widen to ReadWrite.
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{
                RowKey          = 'readeronly'
                Permissions     = '{}'
                PermissionRules = '{"Include":["Identity.User.Read"],"Exclude":[]}'
            }
        }

        (Get-CIPPRolePermissions -RoleName 'readeronly').Permissions | Should -Be @('Identity.User.Read')
    }

    It 'lets an explicit exclude on the .Read win over an implied ReadWrite grant' {
        Mock Get-CippHttpPermissions { @('Endpoint.Device.Read', 'Identity.User.Read') }
        Mock Get-CIPPAzDataTableEntity {
            [PSCustomObject]@{
                RowKey          = 'excluded'
                Permissions     = '{}'
                PermissionRules = '{"Include":["*.ReadWrite"],"Exclude":["Endpoint.Device.Read"]}'
            }
        }

        (Get-CIPPRolePermissions -RoleName 'excluded').Permissions | Should -Be @('Identity.User.Read')
    }

    Context 'legacy rows without PermissionRules' {
        BeforeEach {
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey      = 'legacy'
                    Permissions = '{"IdentityUser":"Identity.User.ReadWrite","IdentityDevice":"Identity.Device.None","CIPPCore":"CIPP.Core.Read","Stale":"Removed.Endpoint.Read"}'
                }
            }
        }

        It 'synthesizes rules in memory, filters to the universe, and surfaces the implied .Read' {
            $Result = Get-CIPPRolePermissions -RoleName 'legacy'
            # Stored values filtered to the valid universe (Removed.Endpoint.Read dropped, None
            # inert), plus the Identity.User.Read implied by the stored Identity.User.ReadWrite.
            $Result.Permissions | Sort-Object | Should -Be @('CIPP.Core.Read', 'Identity.User.Read', 'Identity.User.ReadWrite')
            $Result.PermissionRules.Include | Should -Contain 'Identity.User.ReadWrite'
            $Result.PermissionRules.Include | Should -Not -Contain 'Identity.Device.None'
        }
    }

    Context 'universe unavailable' {
        It 'falls back to the stored snapshot instead of emptying or over-granting' {
            Mock Get-CippHttpPermissions { throw 'cache offline' }
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey          = 'wildcards'
                    Permissions     = '{"IdentityUser":"Identity.User.Read","IdentityDevice":"Identity.Device.None"}'
                    PermissionRules = '{"Include":["*"],"Exclude":[]}'
                }
            }

            $Result = Get-CIPPRolePermissions -RoleName 'wildcards'
            $Result.Permissions | Should -Be @('Identity.User.Read')
        }

        It 'returns an empty set when there is no snapshot either' {
            Mock Get-CippHttpPermissions { throw 'cache offline' }
            Mock Get-CIPPAzDataTableEntity {
                [PSCustomObject]@{
                    RowKey          = 'rulesonly'
                    Permissions     = ''
                    PermissionRules = '{"Include":["*"],"Exclude":[]}'
                }
            }

            @((Get-CIPPRolePermissions -RoleName 'rulesonly').Permissions).Count | Should -Be 0
        }
    }

    It 'throws for an unknown role' {
        Mock Get-CIPPAzDataTableEntity { $null }
        { Get-CIPPRolePermissions -RoleName 'missing' } | Should -Throw '*not found*'
    }
}

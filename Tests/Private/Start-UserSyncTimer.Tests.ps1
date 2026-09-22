# Pester tests for the stale-role self-heal in Start-UserSyncTimer (the 15-minute user sync).
#
# The sync derives each user's auto-roles from the AccessRoleGroups table. When a role's
# group mapping survives (a migration, say) but its definition in CustomRoles does not, the
# user is left carrying an auto-role that Test-CIPPAccess cannot resolve - which denies every
# request, base role included. The fix makes the sync skip mappings whose role no longer
# exists, so the orphaned auto-role drops off every affected user on the next run instead of
# being re-stamped forever. A failed CustomRoles lookup must NOT be read as "no roles exist"
# (that would strip every custom role from everyone), so it degrades to pruning nothing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Start-UserSyncTimer.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Start-UserSyncTimer.ps1 under Modules/' }

    # Shims so Mock has real commands to intercept. Get-CippTable stays a plain shim - it just
    # tags each table so the storage mocks can route on TableName.
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath
}

Describe 'Start-UserSyncTimer - stale role self-heal' {
    BeforeEach {
        # editor is a base role and maps to its group; 'service team' maps to a group too but
        # has no CustomRoles definition on this instance - it is the orphan to prune.
        $script:AccessGroups = @(
            [pscustomobject]@{ PartitionKey = 'AccessRoleGroups'; RowKey = 'editor'; GroupId = 'grp-editor'; GroupName = 'SG-APP-CIPP-editor' }
            [pscustomobject]@{ PartitionKey = 'AccessRoleGroups'; RowKey = 'service team'; GroupId = 'grp-serviceteam'; GroupName = 'SG-APP-CIPP-serviceteam' }
        )
        # Only servicedesk is actually defined - 'service team' is deliberately absent.
        $script:CustomRoles = @(
            [pscustomobject]@{ PartitionKey = 'CustomRoles'; RowKey = 'servicedesk' }
        )
        $script:CustomRolesThrow = $false
        # The affected user already carries the phantom role from a prior (pre-fix) run.
        $script:ExistingUsers = @(
            [pscustomobject]@{
                PartitionKey = 'User'
                RowKey       = 'aaron.macleod@centaris.com'
                Roles        = '["editor","service team"]'
                AutoRoles    = '["editor","service team"]'
                ManualRoles  = '[]'
                Source       = 'Auto'
                LastSync     = '2026-08-17T00:00:00.0000000Z'
            }
        )

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            switch ($TableName) {
                'AccessRoleGroups' { return $script:AccessGroups }
                'CustomRoles' { if ($script:CustomRolesThrow) { throw 'storage unavailable' }; return $script:CustomRoles }
                'allowedUsers' { return $script:ExistingUsers }
                default { return @() }
            }
        }

        # Both groups contain the same single member.
        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($uri -like '*grp-editor*' -or $uri -like '*grp-serviceteam*') {
                return @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'Aaron.MacLeod@centaris.com'; accountEnabled = $true })
            }
            return @()
        }
    }

    It 'never queries the group whose role has no definition' {
        $null = Start-UserSyncTimer

        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*grp-serviceteam*' }
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*grp-editor*' }
    }

    It 'rewrites the affected user with the orphaned auto-role stripped' {
        $null = Start-UserSyncTimer

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'allowedUsers' -and
            $Entity.RowKey -eq 'aaron.macleod@centaris.com' -and
            $Entity.Roles -eq '["editor"]' -and
            $Entity.AutoRoles -eq '["editor"]'
        }
    }

    It 'logs which orphaned role it pruned, on the run that prunes it' {
        $null = Start-UserSyncTimer

        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $sev -eq 'Info' -and $message -like '*Pruned auto-role*' -and $message -like '*service team*'
        }
    }

    It 'keeps the role when the CustomRoles lookup fails, rather than stripping everything' {
        $script:CustomRolesThrow = $true

        $null = Start-UserSyncTimer

        # Unknown validity => prune nothing: the phantom group is still queried and the role kept.
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*grp-serviceteam*' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'allowedUsers' -and $Entity.Roles -eq '["editor","service team"]'
        }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $sev -eq 'Warning' -and $message -like '*could not load custom roles*'
        }
    }
}

# B2B guests carry a UPN like user_home.com#EXT#@tenant.onmicrosoft.com. '#' is illegal in a Table
# Storage RowKey (the OutOfRangeInput crash in issue #458), and with a multi-tenant sign-in the token
# presents the guest's home email (their 'mail'), not the #EXT# UPN. The sync must key the row on a
# clean, matchable identity so the write succeeds AND the auth layer can look the guest up.
Describe 'Start-UserSyncTimer - B2B guest keying' {
    BeforeEach {
        $script:AccessGroups = @(
            [pscustomobject]@{ PartitionKey = 'AccessRoleGroups'; RowKey = 'editor'; GroupId = 'grp-editor'; GroupName = 'SG-APP-CIPP-editor' }
        )
        $script:CustomRoles = @()
        $script:ExistingUsers = @()
        $script:GuestMember = $null

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            switch ($TableName) {
                'AccessRoleGroups' { return $script:AccessGroups }
                'CustomRoles' { return $script:CustomRoles }
                'allowedUsers' { return $script:ExistingUsers }
                default { return @() }
            }
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($uri -like '*grp-editor*') { return @($script:GuestMember) }
            return @()
        }
    }

    It 'keys a guest on their mail (home email), never the #EXT# UPN' {
        $script:GuestMember = [pscustomobject]@{
            '@odata.type'     = '#microsoft.graph.user'
            userPrincipalName = 'zr-dev_dev.johnwduprey.com#EXT#@contoso.onmicrosoft.com'
            mail              = 'ZR-Dev@dev.johnwduprey.com'
            accountEnabled    = $true
        }

        $null = Start-UserSyncTimer

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'allowedUsers' -and
            $Entity.RowKey -eq 'zr-dev@dev.johnwduprey.com' -and
            $Entity.RowKey -notmatch '#'
        }
    }

    It 'decodes the #EXT# UPN back to the invited address when mail is missing' {
        $script:GuestMember = [pscustomobject]@{
            '@odata.type'     = '#microsoft.graph.user'
            userPrincipalName = 'bob_smith_fabrikam.com#EXT#@contoso.onmicrosoft.com'
            mail              = $null
            accountEnabled    = $true
        }

        $null = Start-UserSyncTimer

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'allowedUsers' -and
            $Entity.RowKey -eq 'bob_smith@fabrikam.com' -and
            $Entity.RowKey -notmatch '#'
        }
    }
}

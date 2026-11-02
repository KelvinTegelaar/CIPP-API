# Pester tests for Set-CIPPCopyGroupMembers.
#
# This is the "Copy groups from user" path, reachable from both the Add User form (copyFrom) and
# Edit User. It is a fourth independent implementation of the Exchange-vs-Graph routing decision,
# and unlike the option-driven ones it derives the answer from the group object itself - which is
# the pattern the others were brought in line with.
#
# It also has to be selective about which memberships are copyable at all: dynamic groups, groups
# synced from on-prem AD and public groups are excluded, as are groups the target user is already
# in. When Exchange has not yet provisioned the new recipient the copy is deferred to a scheduled
# task instead of failing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPCopyGroupMembers.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPCopyGroupMembers.ps1 under Modules/' }

    function New-GraphBulkRequest { param($Requests, $tenantid, $scope, $asapp) }
    function New-GraphPostRequest { param($uri, $tenantid, $body, $type, $AsApp) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $UseSystemMailbox) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, $DisallowDuplicateName) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath

    # A group as it comes back from users/{id}/memberOf.
    function New-Group {
        param(
            [string]$Id,
            [string]$DisplayName,
            [bool]$MailEnabled = $false,
            [string[]]$GroupTypes = @(),
            [string[]]$ResourceProvisioningOptions = @(),
            [bool]$OnPremisesSyncEnabled = $false,
            [string]$Visibility = 'Private'
        )
        [pscustomobject]@{
            '@odata.type'               = '#microsoft.graph.group'
            id                          = $Id
            displayName                 = $DisplayName
            MailEnabled                 = $MailEnabled
            groupTypes                  = $GroupTypes
            ResourceProvisioningOptions = $ResourceProvisioningOptions
            onPremisesSyncEnabled       = $OnPremisesSyncEnabled
            visibility                  = $Visibility
        }
    }

    # The mock scriptblock runs long after the helper returns, so the data it serves lives in
    # script scope rather than being captured from a function parameter.
    function Set-BulkResponse {
        param($SourceGroups, $TargetGroups = @(), $AssignedLicenses = @())
        $script:SourceGroups = @($SourceGroups)
        $script:TargetGroups = @($TargetGroups)
        $script:AssignedLicenses = @($AssignedLicenses)
    }
}

Describe 'Set-CIPPCopyGroupMembers' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphPostRequest -MockWith { }
        Mock -CommandName New-ExoRequest -MockWith { }
        Mock -CommandName Add-CIPPScheduledTask -MockWith { }
        Set-BulkResponse -SourceGroups @()
        Mock -CommandName New-GraphBulkRequest -MockWith {
            @(
                [pscustomobject]@{ id = 'User'; body = [pscustomobject]@{ id = 'target-guid'; assignedLicenses = $script:AssignedLicenses } }
                [pscustomobject]@{ id = 'UserMembership'; body = [pscustomobject]@{ value = $script:TargetGroups } }
                [pscustomobject]@{ id = 'CopyFromMembership'; body = [pscustomobject]@{ value = $script:SourceGroups } }
            )
        }
    }

    Context 'Routing each copied membership' {
        It 'copies a plain security group through Graph' {
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-sec' -DisplayName 'All-Users')

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like '*/groups/group-sec/members/$ref' -and $body -like '*directoryObjects/target-guid*'
            }
            Should -Invoke New-ExoRequest -Times 0 -Exactly
            $Result.Success | Should -Contain 'Added user to group: All-Users'
        }

        It 'copies a classic distribution list through Exchange' {
            # Mail-enabled, not a Team, not Unified - Graph cannot write this membership.
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true)

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Add-DistributionGroupMember' -and
                $cmdParams.Identity -eq 'group-dl' -and
                $cmdParams.Member -eq 'new.user@contoso.com' -and
                $cmdParams.BypassSecurityGroupManagerCheck -eq $true
            }
            Should -Invoke New-GraphPostRequest -Times 0 -Exactly
            $Result.Success | Should -Contain 'Added user to group: All Office'
        }

        It 'copies a Microsoft 365 group through Graph even though it is mail-enabled' {
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-m365' -DisplayName 'IEQ - ALL' -MailEnabled $true -GroupTypes @('Unified'))

            $null = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphPostRequest -Times 1 -Exactly
            Should -Invoke New-ExoRequest -Times 0 -Exactly
        }

        It 'copies a Teams-backed group through Graph' {
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-team' -DisplayName 'Compliance Team' -MailEnabled $true -ResourceProvisioningOptions @('Team'))

            $null = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphPostRequest -Times 1 -Exactly
            Should -Invoke New-ExoRequest -Times 0 -Exactly
        }

        It 'copies a mixed membership set to both APIs in one run' {
            Set-BulkResponse -SourceGroups @(
                New-Group -Id 'group-sec' -DisplayName 'All-Users'
                New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true
                New-Group -Id 'group-m365' -DisplayName 'IEQ - ALL' -MailEnabled $true -GroupTypes @('Unified')
            )

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphPostRequest -Times 2 -Exactly
            Should -Invoke New-ExoRequest -Times 1 -Exactly
            $Result.Success.Count | Should -Be 3
        }
    }

    Context 'Memberships that must not be copied' {
        It 'skips a <Reason> and says why' -ForEach @(
            @{ Reason = 'dynamic group'; Expected = 'Skipped Dynamic: its membership is set by a dynamic rule, so members cannot be added directly.'
                Group = @{ Id = 'g'; DisplayName = 'Dynamic'; GroupTypes = @('DynamicMembership') } }
            @{ Reason = 'group synced from on-prem AD'; Expected = 'Skipped Synced: it is synced from on-premises Active Directory and has to be changed there.'
                Group = @{ Id = 'g'; DisplayName = 'Synced'; OnPremisesSyncEnabled = $true } }
            @{ Reason = 'public group'; Expected = 'Skipped Public: it is a public group, which users can join themselves.'
                Group = @{ Id = 'g'; DisplayName = 'Public'; Visibility = 'Public' } }
        ) {
            # A group that is dropped without a word is indistinguishable from one the copy missed.
            Set-BulkResponse -SourceGroups @(New-Group @Group)

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphPostRequest -Times 0 -Exactly
            Should -Invoke New-ExoRequest -Times 0 -Exactly
            $Result.Success | Should -BeNullOrEmpty
            $Result.Error | Should -BeNullOrEmpty
            $Result.Skipped | Should -Contain $Expected
        }

        It 'skips a group the target user is already a member of' {
            $Shared = New-Group -Id 'group-sec' -DisplayName 'All-Users'
            Set-BulkResponse -SourceGroups @($Shared) -TargetGroups @($Shared)

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphPostRequest -Times 0 -Exactly
            $Result.Skipped | Should -Contain 'Already a member of 1 group, left unchanged: All-Users.'
        }

        It 'summarises the already-assigned groups on one line rather than per group' {
            # Copying between two long-standing colleagues would otherwise bury the real outcome.
            $Shared = @(
                New-Group -Id 'group-a' -DisplayName 'Group A'
                New-Group -Id 'group-b' -DisplayName 'Group B'
                New-Group -Id 'group-c' -DisplayName 'Group C'
            )
            Set-BulkResponse -SourceGroups $Shared -TargetGroups $Shared

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            @($Result.Skipped).Count | Should -Be 1
            $Result.Skipped | Should -Contain 'Already a member of 3 groups, left unchanged: Group A, Group B, Group C.'
        }

        It 'reports the skips alongside the groups that did copy' {
            Set-BulkResponse -SourceGroups @(
                New-Group -Id 'group-sec' -DisplayName 'All-Users'
                New-Group -Id 'group-dyn' -DisplayName 'Dynamic' -GroupTypes @('DynamicMembership')
                New-Group -Id 'group-pub' -DisplayName 'Public Team' -Visibility 'Public'
            )

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            $Result.Success | Should -Contain 'Added user to group: All-Users'
            $Result.Skipped | Should -Contain 'Skipped Dynamic: its membership is set by a dynamic rule, so members cannot be added directly.'
            $Result.Skipped | Should -Contain 'Skipped Public Team: it is a public group, which users can join themselves.'
        }

        It 'reports nothing as skipped when every group copied' {
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-sec' -DisplayName 'All-Users')

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            $Result.Skipped | Should -BeNullOrEmpty
        }

        It 'falls back to the group id when it has no display name' {
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-dyn' -DisplayName $null -GroupTypes @('DynamicMembership'))

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            $Result.Skipped | Should -Contain 'Skipped group-dyn: its membership is set by a dynamic rule, so members cannot be added directly.'
        }

        It 'ignores directory roles and other non-group memberships' {
            $Role = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.directoryRole'; id = 'role-1'; displayName = 'Global Reader' }
            Set-BulkResponse -SourceGroups @($Role, (New-Group -Id 'group-sec' -DisplayName 'All-Users'))

            $null = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*group-sec*' }
        }

        It 'copies nothing when the source user has no memberships' {
            Set-BulkResponse -SourceGroups @()

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphPostRequest -Times 0 -Exactly
            $Result.Success | Should -BeNullOrEmpty
            $Result.Error | Should -BeNullOrEmpty
        }
    }

    Context 'Exchange not ready for the new recipient' {
        # A freshly created, licensed user is not yet a usable Exchange recipient. Rather than
        # failing the copy, the Exchange half is deferred and retried.
        It 'schedules an Exchange-only retry when the recipient is not found yet' {
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true) `
                -AssignedLicenses @([pscustomobject]@{ skuId = 'sku-1' })
            Mock -CommandName New-ExoRequest -MockWith { throw 'Ex94914C the recipient could not be found' }

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Command.value -eq 'Set-CIPPCopyGroupMembers' -and
                $Task.Parameters.UserId -eq 'new.user@contoso.com' -and
                $Task.Parameters.CopyFromId -eq 'source-guid' -and
                $Task.Parameters.ExchangeOnly -eq $true -and
                $Task.TenantFilter -eq 'contoso.com'
            }
            $Result.Error | Should -Contain "We've scheduled a task to add new.user@contoso.com to the Exchange group All Office"
        }

        It 'reports the failure instead of scheduling when the user has no licenses' {
            # Without a license there is no mailbox coming, so waiting would never help.
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true)
            Mock -CommandName New-ExoRequest -MockWith { throw 'Ex94914C the recipient could not be found' }

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            $Result.Error | Should -Not -BeNullOrEmpty
        }

        It 'does not touch Graph groups when running as the Exchange-only retry' {
            Set-BulkResponse -SourceGroups @(
                New-Group -Id 'group-sec' -DisplayName 'All-Users'
                New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true
            )

            $null = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com' -ExchangeOnly

            Should -Invoke New-ExoRequest -Times 1 -Exactly
            Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        }

        It 'reports an unrelated Exchange failure rather than scheduling a retry' {
            Set-BulkResponse -SourceGroups @(New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true) `
                -AssignedLicenses @([pscustomobject]@{ skuId = 'sku-1' })
            Mock -CommandName New-ExoRequest -MockWith { throw 'Insufficient permissions' }

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            $Result.Error | Should -Contain "We've failed to add the group All Office: Insufficient permissions"
        }
    }

    Context 'Failure isolation' {
        It 'keeps copying the remaining groups after one fails' {
            Set-BulkResponse -SourceGroups @(
                New-Group -Id 'group-a' -DisplayName 'Group A'
                New-Group -Id 'group-b' -DisplayName 'Group B'
                New-Group -Id 'group-c' -DisplayName 'Group C'
            )
            Mock -CommandName New-GraphPostRequest -MockWith { throw 'boom' } -ParameterFilter { $uri -like '*group-b*' }

            $Result = Set-CIPPCopyGroupMembers -UserId 'new.user@contoso.com' -CopyFromId 'source-guid' -TenantFilter 'contoso.com'

            $Result.Success | Should -Contain 'Added user to group: Group A'
            $Result.Success | Should -Contain 'Added user to group: Group C'
            $Result.Error | Should -Contain "We've failed to add the group Group B: boom"
        }
    }
}

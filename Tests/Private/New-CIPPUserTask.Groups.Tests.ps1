# Pester tests for the "Add to Groups" block of New-CIPPUserTask.
#
# This is the path behind the Add User form and user templates. Each selected group arrives as
# an autocomplete option - { label, value, addedFields } - and the block hands the group id and
# the group type to Add-CIPPGroupMember, then decides whether a failure is worth retrying.
#
# The group type matters because Graph cannot write membership to a classic distribution list.
# Templates saved before addedFields existed (and any option that lost it on the way through the
# form) carry no group type at all, so the block must not assume the caller told it the truth.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'New-CIPPUserTask.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate New-CIPPUserTask.ps1 under Modules/' }

    function New-CIPPUser { param($UserObj, $APIName, $Headers) }
    function Set-CIPPUserLicense { param($UserId, $TenantFilter, $AddLicenses, $Headers, $APIName) }
    function Set-SherwebSubscription { param($Headers, $TenantFilter, $SKU, $Add) }
    function Add-CIPPAlias { param($User, $Aliases, $UserPrincipalName, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPCopyGroupMembers { param($Headers, $CopyFromId, $UserID, $TenantFilter) }
    function Add-CIPPGroupMember { param($Headers, $GroupType, $GroupId, $Member, $TenantFilter, $APIName) }
    function Set-CIPPManager { param($Users, $Manager, $TenantFilter, $Headers) }
    function Set-CIPPSponsor { param($Users, $Sponsor, $TenantFilter, $Headers) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, $DisallowDuplicateName) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    # An autocomplete option as the Add User form posts it. Omit -GroupType to model a template
    # entry that was stored without addedFields.
    function New-GroupOption {
        param([string]$Label, [string]$Value, [string]$GroupType)
        $Option = [pscustomobject]@{ label = $Label; value = $Value }
        if ($PSBoundParameters.ContainsKey('GroupType')) {
            $Option | Add-Member -NotePropertyName addedFields -NotePropertyValue ([pscustomobject]@{ groupType = $GroupType })
        }
        return $Option
    }

    function New-TestUserObj {
        param($AddToGroups)
        [pscustomobject]@{
            tenantFilter = 'contoso.com'
            givenName    = 'Safiyah'
            surname      = 'Seck'
            AddToGroups  = $AddToGroups
        }
    }
}

Describe 'New-CIPPUserTask - Add to Groups' {
    BeforeEach {
        Mock -CommandName New-CIPPUser -MockWith {
            [pscustomobject]@{
                Username = 'sseck@contoso.com'
                Password = 'Correct-Horse-Battery'
                User     = [pscustomobject]@{ id = 'user-guid' }
            }
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPScheduledTask -MockWith { 'Successfully added task.' }
        Mock -CommandName Add-CIPPGroupMember -MockWith { 'Successfully added user sseck@contoso.com to group Contoso Group.' }
    }

    Context 'Handing each selected group to Add-CIPPGroupMember' {
        It 'adds the new user to every selected group' {
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security'
                New-GroupOption -Label 'IEQ - ALL' -Value 'group-2' -GroupType 'Microsoft 365'
                New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType 'Distribution list'
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 3 -Exactly
            foreach ($Expected in 'group-1', 'group-2', 'group-3') {
                Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter {
                    $GroupId -eq $Expected -and
                    $Member -contains 'sseck@contoso.com' -and
                    $TenantFilter -eq 'contoso.com'
                }
            }
            $Result.Results | Should -Contain 'Successfully added user sseck@contoso.com to group Contoso Group.'
        }

        It 'passes the group type through so mail-based groups reach Exchange' {
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType 'Distribution list'
            )

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter {
                $GroupType -eq 'Distribution list'
            }
        }

        It 'keeps going after one group fails so the remaining groups still get processed' {
            # The reported symptom was a run where two distribution lists failed and every other
            # group succeeded; a failure must never abort the rest of the list.
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'Cannot Update a mail-enabled security groups and or distribution list.' } -ParameterFilter { $GroupId -eq 'group-2' }

            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security'
                New-GroupOption -Label 'IEQ-Team' -Value 'group-2' -GroupType 'Security'
                New-GroupOption -Label 'KnowBe4 - All Users' -Value 'group-3' -GroupType 'Security'
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 3 -Exactly
            $Result.Results | Should -Contain 'Failed to add to group IEQ-Team: Cannot Update a mail-enabled security groups and or distribution list.'
        }

        It 'does nothing when no groups were selected' {
            $Result = New-CIPPUserTask -UserObj (New-TestUserObj)

            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
            $Result.Username | Should -Be 'sseck@contoso.com'
        }

        It 'accepts a single group that is not wrapped in an array' {
            $UserObj = New-TestUserObj -AddToGroups (New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security')

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-1' }
        }
    }

    Context 'Retrying groups that Exchange is not ready for' {
        # A brand new user is not a usable Exchange recipient for a few minutes, so an add to a
        # distribution list right after creation often fails on replication lag rather than on
        # anything the operator did wrong. Those are scheduled for a delayed retry.
        It 'schedules a delayed retry when a <GroupType> add fails' -ForEach @(
            @{ GroupType = 'Distribution list' }
            @{ GroupType = 'Mail-Enabled Security' }
        ) {
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'The recipient could not be found.' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType $GroupType
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Command.value -eq 'Add-CIPPGroupMember' -and
                $Task.Parameters.GroupId -eq 'group-3' -and
                $Task.Parameters.GroupType -eq $GroupType -and
                $Task.Parameters.Member -contains 'sseck@contoso.com' -and
                $Task.Parameters.TenantFilter -eq 'contoso.com' -and
                $Task.TenantFilter -eq 'contoso.com' -and
                $DisallowDuplicateName -eq $true
            }
            $Result.Results | Should -Contain 'Could not add sseck@contoso.com to All Office yet (Exchange replication delay). A retry has been scheduled in 15 minutes.'
        }

        It 'schedules the retry 15 minutes out' {
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'The recipient could not be found.' }
            $Expected = [int64](([datetime]::UtcNow).AddMinutes(15) - (Get-Date '1/1/1970')).TotalSeconds
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType 'Distribution list'
            )

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                [math]::Abs($Task.ScheduledTime - $Expected) -lt 60
            }
        }

        It 'reports a plain failure for a directory group instead of scheduling a retry' {
            # Graph adds do not suffer the Exchange replication delay, so a failure there is real.
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'Insufficient privileges' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security'
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            $Result.Results | Should -Contain 'Failed to add to group All-Users: Insufficient privileges'
        }

        It 'still reports a failure when scheduling the retry itself throws' {
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'The recipient could not be found.' }
            Mock -CommandName Add-CIPPScheduledTask -MockWith { throw 'scheduler unavailable' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType 'Distribution list'
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            $Result.Results | Should -Contain 'Failed to add to group All Office: scheduler unavailable'
        }
    }

    Context 'Groups selected from a template that carries no group type' {
        # Templates stored before addedFields existed hold only { label, value }. The block used to
        # pass a null group type straight through, which sent classic distribution lists down the
        # Graph path and produced "Cannot Update a mail-enabled security groups and or distribution
        # list" - the failure the operator sees while every directory group in the same run succeeds.
        It 'still attempts the add when the option carries no addedFields' {
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-3'
            )

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-3' }
        }

        It 'schedules a retry rather than giving up when a typeless group add fails' {
            # Without a group type the block cannot rule out that this is an Exchange group hitting
            # replication lag, so the recoverable path is the correct default.
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'The recipient could not be found.' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-3'
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.GroupId -eq 'group-3'
            }
            $Result.Results | Should -Contain 'Could not add sseck@contoso.com to All Office yet (Exchange replication delay). A retry has been scheduled in 15 minutes.'
        }
    }
}

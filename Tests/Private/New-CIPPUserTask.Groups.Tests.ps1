# Pester tests for the "Add to Groups" block of New-CIPPUserTask.
#
# This is the path behind the Add User form and user templates. Each selected group arrives as
# an autocomplete option - { label, value, addedFields }. The block looks the group up first:
# Exchange-backed groups (distribution lists, mail-enabled security) are always scheduled 15
# minutes out, because a brand-new user is not yet an Exchange recipient; directory groups are
# added inline through Add-CIPPGroupMember.
#
# The live lookup wins over the option's own type fields, which can be missing (older templates),
# stale, or in the calculatedGroupType vocabulary where 'security' means MAIL-ENABLED security.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'New-CIPPUserTask.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate New-CIPPUserTask.ps1 under Modules/' }

    function New-CIPPUser { param($UserObj, $APIName, $Headers) }
    function Set-CIPPUserLicense { param($UserId, $TenantFilter, $AddLicenses, $Headers, $APIName) }
    function Set-SherwebSubscription { param($Headers, $TenantFilter, $SKU, $Add) }
    function Add-CIPPAlias { param($User, $Aliases, $UserPrincipalName, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPCopyGroupMembers { param($Headers, $CopyFromId, $UserID, $TenantFilter, [switch]$DeferExchange) }
    function Add-CIPPGroupMember { param($Headers, $GroupType, $GroupId, $Member, $TenantFilter, $APIName) }
    function Set-CIPPManager { param($Users, $Manager, $TenantFilter, $Headers) }
    function Set-CIPPSponsor { param($Users, $Sponsor, $TenantFilter, $Headers) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, $DisallowDuplicateName) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPGroupType { param($GroupId, $TenantFilter, $FallbackGroupType) }

    . $FunctionPath
    . (Join-Path (Split-Path -Parent $FunctionPath) 'Test-CIPPGroupIsExchangeBacked.ps1')

    # What Get-CIPPGroupType returns. -Unresolved models Graph and Exchange both failing to answer,
    # where it falls back to 'Security' with no group object.
    function New-GroupLookup {
        param([string]$GroupType, [switch]$Unresolved)
        if ($Unresolved) {
            return [pscustomobject]@{ GroupType = 'Security'; IsExchangeBacked = $false; GroupObject = $null }
        }
        [pscustomobject]@{
            GroupType        = $GroupType
            IsExchangeBacked = $GroupType -in @('Distribution List', 'Mail-Enabled Security')
            GroupObject      = [pscustomobject]@{ mailEnabled = $GroupType -ne 'Security'; securityEnabled = $GroupType -ne 'Distribution List' }
        }
    }

    # Live type per group id, read by the Get-CIPPGroupType mock.
    function Set-LiveGroupTypes {
        param([hashtable]$Types)
        $script:LiveGroupTypes = $Types
    }

    # An autocomplete option as the Add User form posts it. Omit -GroupType to model a template
    # entry that was stored without addedFields.
    function New-GroupOption {
        param([string]$Label, [string]$Value, [string]$GroupType, [string]$CalculatedGroupType)
        $Option = [pscustomobject]@{ label = $Label; value = $Value }
        if ($PSBoundParameters.ContainsKey('GroupType') -or $PSBoundParameters.ContainsKey('CalculatedGroupType')) {
            $Added = [pscustomobject]@{}
            if ($PSBoundParameters.ContainsKey('GroupType')) { $Added | Add-Member -NotePropertyName groupType -NotePropertyValue $GroupType }
            if ($PSBoundParameters.ContainsKey('CalculatedGroupType')) { $Added | Add-Member -NotePropertyName calculatedGroupType -NotePropertyValue $CalculatedGroupType }
            $Option | Add-Member -NotePropertyName addedFields -NotePropertyValue $Added
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
        Mock -CommandName Add-CIPPScheduledTask -MockWith { 'Successfully added task: Add Group Member. It will run in 15 minutes.' }
        Mock -CommandName Add-CIPPGroupMember -MockWith { 'Successfully added user sseck@contoso.com to group Contoso Group.' }
        Set-LiveGroupTypes @{}
        Mock -CommandName Get-CIPPGroupType -MockWith {
            $Live = $script:LiveGroupTypes[$GroupId]
            if ($Live) { New-GroupLookup -GroupType $Live } else { New-GroupLookup -Unresolved }
        }
    }

    Context 'Directory groups are added inline' {
        It 'adds the new user to every selected directory group' {
            Set-LiveGroupTypes @{ 'group-1' = 'Security'; 'group-2' = 'Microsoft 365' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security'
                New-GroupOption -Label 'IEQ - ALL' -Value 'group-2' -GroupType 'Microsoft 365'
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 2 -Exactly
            foreach ($Expected in 'group-1', 'group-2') {
                Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter {
                    $GroupId -eq $Expected -and
                    $Member -contains 'sseck@contoso.com' -and
                    $TenantFilter -eq 'contoso.com'
                }
            }
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            $Result.Results | Should -Contain 'Successfully added user sseck@contoso.com to group Contoso Group.'
        }

        It 'adds inline when the template says Security and the live group is plain Security' {
            Set-LiveGroupTypes @{ 'group-1' = 'Security' }
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security')

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-1' -and $GroupType -eq 'Security' }
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }

        It 'adds inline when the template claims a distribution list but the live group is a directory group' {
            # A stale saved type must not defer a group Graph can write right now.
            Set-LiveGroupTypes @{ 'group-1' = 'Microsoft 365' }
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'Converted' -Value 'group-1' -GroupType 'Distribution list')

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }

        It 'reports a plain failure for a directory group instead of scheduling a retry' {
            # Graph adds do not suffer the Exchange replication delay, so a failure there is real.
            Set-LiveGroupTypes @{ 'group-1' = 'Security' }
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'Insufficient privileges' }
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security')

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            $Result.Results | Should -Contain 'Failed to add to group All-Users: Insufficient privileges'
        }

        It 'keeps going after one group fails so the remaining groups still get processed' {
            Set-LiveGroupTypes @{ 'group-1' = 'Security'; 'group-2' = 'Security'; 'group-3' = 'Security' }
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'Request failed' } -ParameterFilter { $GroupId -eq 'group-2' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security'
                New-GroupOption -Label 'IEQ-Team' -Value 'group-2' -GroupType 'Security'
                New-GroupOption -Label 'KnowBe4 - All Users' -Value 'group-3' -GroupType 'Security'
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 3 -Exactly
            $Result.Results | Should -Contain 'Failed to add to group IEQ-Team: Request failed'
        }

        It 'does nothing when no groups were selected' {
            $Result = New-CIPPUserTask -UserObj (New-TestUserObj)

            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
            Should -Invoke Get-CIPPGroupType -Times 0 -Exactly
            $Result.Username | Should -Be 'sseck@contoso.com'
        }

        It 'accepts a single group that is not wrapped in an array' {
            Set-LiveGroupTypes @{ 'group-1' = 'Security' }
            $UserObj = New-TestUserObj -AddToGroups (New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security')

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-1' }
        }
    }

    Context 'Exchange-backed groups are scheduled, never attempted inline' {
        # A brand new user is not a usable Exchange recipient for a few minutes, so an inline add
        # would fail every time. The add is queued instead and reported as a normal step.
        It 'schedules a live <LiveType> without calling Add-CIPPGroupMember' -ForEach @(
            @{ LiveType = 'Distribution List' }
            @{ LiveType = 'Mail-Enabled Security' }
        ) {
            Set-LiveGroupTypes @{ 'group-3' = $LiveType }
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType 'Distribution list')

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Command.value -eq 'Add-CIPPGroupMember' -and
                $Task.Parameters.GroupId -eq 'group-3' -and
                $Task.Parameters.GroupType -eq $LiveType -and
                $Task.Parameters.Member -contains 'sseck@contoso.com' -and
                $Task.Parameters.TenantFilter -eq 'contoso.com' -and
                $Task.TenantFilter -eq 'contoso.com' -and
                $DisallowDuplicateName -eq $true
            }
            $Result.Results | Should -Contain 'Scheduled adding sseck@contoso.com to All Office in 15 minutes, once Exchange has provisioned the mailbox.'
        }

        It "schedules when the template says 'security' (calculatedGroupType vocabulary) and the live group is mail-enabled security" {
            # 'security' in that vocabulary means mail-enabled; read as Graph security it used to be
            # attempted inline and failed with the recipient-not-found error.
            Set-LiveGroupTypes @{ 'group-3' = 'Mail-Enabled Security' }
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'Finance MES' -Value 'group-3' -GroupType 'security')

            $Result = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.GroupId -eq 'group-3' -and $Task.Parameters.GroupType -eq 'Mail-Enabled Security'
            }
            $Result.Results | Should -Contain 'Scheduled adding sseck@contoso.com to Finance MES in 15 minutes, once Exchange has provisioned the mailbox.'
        }

        It 'schedules the add 15 minutes out' {
            Set-LiveGroupTypes @{ 'group-3' = 'Distribution List' }
            $Expected = [int64](([datetime]::UtcNow).AddMinutes(15) - (Get-Date '1/1/1970')).TotalSeconds
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All Office' -Value 'group-3')

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                [math]::Abs($Task.ScheduledTime - $Expected) -lt 60
            }
        }

        It 'schedules Exchange groups and adds directory groups inline in the same run' {
            Set-LiveGroupTypes @{ 'group-1' = 'Security'; 'group-3' = 'Distribution List' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security'
                New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType 'Distribution list'
            )

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-1' }
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $Task.Parameters.GroupId -eq 'group-3' }
        }

        It 'reports a failure when the scheduler returns an error string' {
            Set-LiveGroupTypes @{ 'group-3' = 'Distribution List' }
            Mock -CommandName Add-CIPPScheduledTask -MockWith { 'Task with this name already exists' }
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All Office' -Value 'group-3')

            $Result = New-CIPPUserTask -UserObj $UserObj

            $Result.Results | Should -Contain 'Failed to schedule adding to group All Office: Task with this name already exists'
        }

        It 'still reports a failure when scheduling itself throws, and carries on with the next group' {
            Set-LiveGroupTypes @{ 'group-3' = 'Distribution List'; 'group-1' = 'Security' }
            Mock -CommandName Add-CIPPScheduledTask -MockWith { throw 'scheduler unavailable' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-3'
                New-GroupOption -Label 'All-Users' -Value 'group-1'
            )

            $Result = New-CIPPUserTask -UserObj $UserObj

            $Result.Results | Should -Contain 'Failed to add to group All Office: scheduler unavailable'
            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-1' }
        }
    }

    Context 'Copying groups from another user' {
        It 'defers the Exchange half of the copy because the user was just created' {
            Mock -CommandName Set-CIPPCopyGroupMembers -MockWith { [pscustomobject]@{ Success = @(); Error = @(); Skipped = @() } }
            $UserObj = New-TestUserObj
            $UserObj | Add-Member -NotePropertyName copyFrom -NotePropertyValue ([pscustomobject]@{ value = 'source-guid' })

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Set-CIPPCopyGroupMembers -Times 1 -Exactly -ParameterFilter { $DeferExchange.IsPresent -and $CopyFromId -eq 'source-guid' }
        }
    }

    Context 'Groups the live lookup cannot classify' {
        # Only when Graph and Exchange both fail to answer do the option's saved fields decide,
        # with the same rule Set-CIPPUser uses.
        It 'schedules when the saved calculatedGroupType is <Calculated>' -ForEach @(
            @{ Calculated = 'distributionList' }
            @{ Calculated = 'security' }
        ) {
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType 'Security' -CalculatedGroupType $Calculated)

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly
        }

        It 'schedules when only the saved groupType says distribution list' {
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All Office' -Value 'group-3' -GroupType 'Distribution list')

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly
        }

        It 'schedules rather than adding inline when the option carries no type at all' {
            # An unknown group is more likely Exchange with a transient lookup failure, and an inline
            # Exchange add on a brand-new user always fails.
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All Office' -Value 'group-3')

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Parameters.GroupId -eq 'group-3' -and $Task.Parameters.GroupType -eq 'Distribution List'
            }
        }

        It 'adds inline when the lookup fails but the option says plain security (generic)' {
            $UserObj = New-TestUserObj -AddToGroups @(New-GroupOption -Label 'All-Users' -Value 'group-1' -GroupType 'Security' -CalculatedGroupType 'generic')

            $null = New-CIPPUserTask -UserObj $UserObj

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-1' }
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }
    }
}

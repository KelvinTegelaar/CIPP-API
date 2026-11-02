# Pester tests for the group add/remove blocks of Set-CIPPUser (the Edit User page).
#
# Set-CIPPUser carries its own copy of the "does this group live in Exchange or in the directory"
# decision, separate from Add-CIPPGroupMember. It reads the type off the autocomplete option the
# form posted: calculatedGroupType when present, otherwise the display groupType. Getting it wrong
# means Graph is asked to change membership on a classic distribution list, which it refuses with
# "Cannot Update a mail-enabled security groups and or distribution list".
#
# Note the vocabulary mismatch between the two fields, which is easy to misread: in
# calculatedGroupType, 'security' means a MAIL-ENABLED security group (Exchange) while 'generic'
# means a plain security group (Graph).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPUser.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPUser.ps1 under Modules/' }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $ComplexFilter, $Select) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $scope, $asapp) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $UseSystemMailbox) }
    function Set-CIPPUserLicense { param($UserId, $TenantFilter, $AddLicenses, $RemoveLicenses, $Headers, $APIName) }
    function Set-CIPPCopyGroupMembers { param($Headers, $CopyFromId, $UserID, $TenantFilter) }
    function Add-CIPPAlias { param($User, $Aliases, $UserPrincipalName, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPManager { param($Users, $Manager, $TenantFilter, $Headers) }
    function Set-CIPPSponsor { param($Users, $Sponsor, $TenantFilter, $Headers) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-NormalizedError { param($message) $message }

    . $FunctionPath

    # An autocomplete option as the Edit User form posts it. The options are built from
    # /api/ListGroups, which supplies both type fields.
    function New-GroupOption {
        param([string]$Label, [string]$Value, [string]$GroupType, [string]$CalculatedGroupType)
        $Added = [pscustomobject]@{}
        if ($PSBoundParameters.ContainsKey('GroupType')) {
            $Added | Add-Member -NotePropertyName groupType -NotePropertyValue $GroupType
        }
        if ($PSBoundParameters.ContainsKey('CalculatedGroupType')) {
            $Added | Add-Member -NotePropertyName calculatedGroupType -NotePropertyValue $CalculatedGroupType
        }
        [pscustomobject]@{ label = $Label; value = $Value; addedFields = $Added }
    }

    # What Graph says each group is, served by the bulk-lookup mock in BeforeEach.
    function Set-GroupLookup {
        param([hashtable[]]$Groups)
        $script:GroupLookup = @($Groups)
    }

    function New-TestUserObj {
        param($AddToGroups, $RemoveFromGroups)
        [pscustomobject]@{
            id               = 'user-guid'
            tenantFilter     = 'contoso.com'
            username         = 'sseck'
            Domain           = 'contoso.com'
            DisplayName      = 'Safiyah Seck'
            AddToGroups      = $AddToGroups
            RemoveFromGroups = $RemoveFromGroups
        }
    }
}

Describe 'Set-CIPPUser - group membership' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphPostRequest -MockWith { }
        Mock -CommandName New-ExoRequest -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        Mock -CommandName Set-CIPPCopyGroupMembers -MockWith { [PSCustomObject]@{ Success = @(); Error = @() } }
        # By default the group lookup tells us nothing, so the option's own fields decide.
        # The mock reads script scope because it runs long after Set-GroupLookup has returned.
        $script:GroupLookup = @()
        Mock -CommandName New-GraphBulkRequest -MockWith {
            foreach ($Group in $script:GroupLookup) {
                [pscustomobject]@{
                    id     = $Group.id
                    status = 200
                    body   = [pscustomobject]@{
                        id              = $Group.id
                        groupTypes      = $Group.groupTypes ?? @()
                        mailEnabled     = $Group.mailEnabled
                        securityEnabled = $Group.securityEnabled
                    }
                }
            }
        }
    }

    Context 'Adding a user to a group' {
        It 'sends a <Label> to <Route>' -ForEach @(
            @{ Label = 'classic distribution list'; Calculated = 'distributionList'; Display = 'Distribution List'; Route = 'Exchange'; Exo = 1; Graph = 0 }
            @{ Label = 'mail-enabled security group'; Calculated = 'security'; Display = 'Mail-Enabled Security'; Route = 'Exchange'; Exo = 1; Graph = 0 }
            @{ Label = 'plain security group'; Calculated = 'generic'; Display = 'Security'; Route = 'Graph'; Exo = 0; Graph = 1 }
            @{ Label = 'Microsoft 365 group'; Calculated = 'm365'; Display = 'Microsoft 365'; Route = 'Graph'; Exo = 0; Graph = 1 }
        ) {
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'Target' -Value 'group-1' -GroupType $Display -CalculatedGroupType $Calculated
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times $Exo -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
            Should -Invoke New-GraphPostRequest -Times $Graph -Exactly -ParameterFilter { $uri -like '*/groups/group-1/members/*' -and $type -eq 'POST' }
        }

        It 'passes the group and the user through to Add-DistributionGroupMember' {
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-dl' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
            )

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Add-DistributionGroupMember' -and
                $cmdParams.Identity -eq 'group-dl' -and
                $cmdParams.Member -eq 'user-guid' -and
                $cmdParams.BypassSecurityGroupManagerCheck -eq $true -and
                $tenantid -eq 'contoso.com'
            }
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been added to All Office'
        }

        It 'binds the user as a directory object when adding through Graph' {
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-sec' -GroupType 'Security' -CalculatedGroupType 'generic'
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
                $body -like '*directoryObjects/user-guid*'
            }
        }

        It 'falls back to the display group type when calculatedGroupType is absent' {
            # Options stored before calculatedGroupType existed only carry the display string.
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-dl' -GroupType 'Distribution List'
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
        }

        It 'processes every selected group' {
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-dl' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
                New-GroupOption -Label 'All-Users' -Value 'group-sec' -GroupType 'Security' -CalculatedGroupType 'generic'
            )

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*group-sec*' }
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been added to All Office'
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been added to All-Users'
        }

        It 'reports a failed group without aborting the rest of the edit' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'Cannot Update a mail-enabled security groups and or distribution list.' } -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-dl' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
                New-GroupOption -Label 'All-Users' -Value 'group-sec' -GroupType 'Security' -CalculatedGroupType 'generic'
            )

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            $Result.Results | Should -Contain 'Failed to add member Safiyah Seck to All Office. Error: Cannot Update a mail-enabled security groups and or distribution list.'
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been added to All-Users'
        }

        It 'touches no group API when nothing was selected' {
            $null = Set-CIPPUser -UserObj (New-TestUserObj) -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
            Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*/members/*' }
        }
    }

    Context 'Removing a user from a group' {
        It 'sends a <Label> to <Route>' -ForEach @(
            @{ Label = 'classic distribution list'; Calculated = 'distributionList'; Display = 'Distribution List'; Route = 'Exchange'; Exo = 1; Graph = 0 }
            @{ Label = 'mail-enabled security group'; Calculated = 'security'; Display = 'Mail-Enabled Security'; Route = 'Exchange'; Exo = 1; Graph = 0 }
            @{ Label = 'plain security group'; Calculated = 'generic'; Display = 'Security'; Route = 'Graph'; Exo = 0; Graph = 1 }
        ) {
            $UserObj = New-TestUserObj -RemoveFromGroups @(
                New-GroupOption -Label 'Target' -Value 'group-1' -GroupType $Display -CalculatedGroupType $Calculated
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times $Exo -Exactly -ParameterFilter { $cmdlet -eq 'Remove-DistributionGroupMember' }
            Should -Invoke New-GraphPostRequest -Times $Graph -Exactly -ParameterFilter { $type -eq 'DELETE' }
        }

        It 'deletes the membership reference for the specific user through Graph' {
            $UserObj = New-TestUserObj -RemoveFromGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-sec' -GroupType 'Security' -CalculatedGroupType 'generic'
            )

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like '*/groups/group-sec/members/user-guid/*' -and $type -eq 'DELETE'
            }
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been removed from All-Users'
        }

        It 'reports a failed removal against the group it belongs to' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'The user is not a member of the group.' } -ParameterFilter { $cmdlet -eq 'Remove-DistributionGroupMember' }
            $UserObj = New-TestUserObj -RemoveFromGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-dl' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
            )

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            $Result.Results | Should -Contain 'Failed to remove member Safiyah Seck from All Office. Error: The user is not a member of the group.'
        }
    }

    Context 'Copying group membership from another user' {
        # Set-CIPPCopyGroupMembers returns one object with a Success list and an Error list. Adding
        # it to the results wholesale rendered the entire copy as
        # "@{Success=System.Object[]; Error=System.Object[]}" on the Edit User page, so neither the
        # groups that copied nor the ones that failed reached the operator. Caught against a live
        # tenant; the Add User path never had this because it flattens the object itself.
        It 'reports each copied group individually' {
            Mock -CommandName Set-CIPPCopyGroupMembers -MockWith {
                [PSCustomObject]@{
                    Success = @('Added user to group: All-Users', 'Added user to group: All Office')
                    Error   = @()
                }
            }
            $UserObj = New-TestUserObj
            $UserObj | Add-Member -NotePropertyName CopyFrom -NotePropertyValue ([pscustomobject]@{ value = 'source-guid' })

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            $Result.Results | Should -Contain 'Added user to group: All-Users'
            $Result.Results | Should -Contain 'Added user to group: All Office'
            "$($Result.Results)" | Should -Not -BeLike '*System.Object*'
        }

        It 'surfaces the groups that could not be copied' {
            Mock -CommandName Set-CIPPCopyGroupMembers -MockWith {
                [PSCustomObject]@{
                    Success = @('Added user to group: All-Users')
                    Error   = @("We've failed to add the group All Office: Insufficient privileges")
                }
            }
            $UserObj = New-TestUserObj
            $UserObj | Add-Member -NotePropertyName CopyFrom -NotePropertyValue ([pscustomobject]@{ value = 'source-guid' })

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            $Result.Results | Should -Contain 'Added user to group: All-Users'
            $Result.Results | Should -Contain "We've failed to add the group All Office: Insufficient privileges"
        }

        It 'passes the deliberately skipped groups through to the operator' {
            # Otherwise a group the copy chose not to touch is indistinguishable from one it missed.
            Mock -CommandName Set-CIPPCopyGroupMembers -MockWith {
                [PSCustomObject]@{
                    Success = @('Added user to group: All-Users')
                    Error   = @()
                    Skipped = @(
                        'Skipped Dynamic: its membership is set by a dynamic rule, so members cannot be added directly.'
                        'Already a member of 2 groups, left unchanged: Retail, MSFT.'
                    )
                }
            }
            $UserObj = New-TestUserObj
            $UserObj | Add-Member -NotePropertyName CopyFrom -NotePropertyValue ([pscustomobject]@{ value = 'source-guid' })

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            $Result.Results | Should -Contain 'Added user to group: All-Users'
            $Result.Results | Should -Contain 'Skipped Dynamic: its membership is set by a dynamic rule, so members cannot be added directly.'
            $Result.Results | Should -Contain 'Already a member of 2 groups, left unchanged: Retail, MSFT.'
        }

        It 'adds nothing when the copy produced no outcomes' {
            Mock -CommandName Set-CIPPCopyGroupMembers -MockWith {
                [PSCustomObject]@{ Success = @(); Error = @() }
            }
            $UserObj = New-TestUserObj
            $UserObj | Add-Member -NotePropertyName CopyFrom -NotePropertyValue ([pscustomobject]@{ value = 'source-guid' })

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            "$($Result.Results)" | Should -Not -BeLike '*System.Object*'
        }

        It 'does not copy when no source user was chosen' {
            $null = Set-CIPPUser -UserObj (New-TestUserObj) -APIName 'Edit User'

            Should -Invoke Set-CIPPCopyGroupMembers -Times 0 -Exactly
        }
    }

    Context 'Adds and removals in the same edit' {
        It 'runs both lists independently' {
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-dl' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
            ) -RemoveFromGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-sec' -GroupType 'Security' -CalculatedGroupType 'generic'
            )

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'DELETE' }
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been added to All Office'
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been removed from All-Users'
        }
    }

    Context 'Resolving the group type from the group itself' {
        # The posted type is whatever the form held when the option was built: absent on older
        # saved selections, stale on any group converted since. One bulk lookup settles what each
        # group really is, and that answer overrides the option.
        It 'sends a classic distribution list to Exchange even when the option carries no type' {
            Set-GroupLookup -Groups @(@{ id = 'group-dl'; mailEnabled = $true; securityEnabled = $false })
            $UserObj = New-TestUserObj -AddToGroups @(
                [pscustomobject]@{ label = 'All Office'; value = 'group-dl' }
            )

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
            Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*group-dl*' }
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been added to All Office'
        }

        It 'overrides an option that disagrees with the group' {
            Set-GroupLookup -Groups @(@{ id = 'group-dl'; mailEnabled = $true; securityEnabled = $false })
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'IEQ-Team' -Value 'group-dl' -GroupType 'Security' -CalculatedGroupType 'generic'
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
        }

        It 'routes a mail-enabled security group to Exchange' {
            Set-GroupLookup -Groups @(@{ id = 'group-mes'; mailEnabled = $true; securityEnabled = $true })
            $UserObj = New-TestUserObj -AddToGroups @(
                [pscustomobject]@{ label = 'SG-LIC-M365'; value = 'group-mes' }
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
        }

        It 'keeps a Microsoft 365 group on Graph even though it is mail-enabled' {
            Set-GroupLookup -Groups @(@{ id = 'group-m365'; groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false })
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'IEQ - ALL' -Value 'group-m365' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 0 -Exactly
            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*group-m365*' }
        }

        It 'keeps a plain security group on Graph' {
            Set-GroupLookup -Groups @(@{ id = 'group-sec'; mailEnabled = $false; securityEnabled = $true })
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All-Users' -Value 'group-sec' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 0 -Exactly
            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*group-sec*' }
        }

        It 'resolves removals as well as adds' {
            Set-GroupLookup -Groups @(@{ id = 'group-dl'; mailEnabled = $true; securityEnabled = $false })
            $UserObj = New-TestUserObj -RemoveFromGroups @(
                [pscustomobject]@{ label = 'All Office'; value = 'group-dl' }
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Remove-DistributionGroupMember' }
        }

        It 'looks every group in the request up in a single call' {
            Set-GroupLookup -Groups @(
                @{ id = 'group-dl'; mailEnabled = $true; securityEnabled = $false }
                @{ id = 'group-sec'; mailEnabled = $false; securityEnabled = $true }
            )
            $UserObj = New-TestUserObj -AddToGroups @(
                [pscustomobject]@{ label = 'All Office'; value = 'group-dl' }
            ) -RemoveFromGroups @(
                [pscustomobject]@{ label = 'All-Users'; value = 'group-sec' }
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests.Count -eq 2 -and $Requests.id -contains 'group-dl' -and $Requests.id -contains 'group-sec'
            }
        }

        It 'does not call Graph at all when the request changes no groups' {
            $null = Set-CIPPUser -UserObj (New-TestUserObj) -APIName 'Edit User'

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }

        It 'falls back to the option when the lookup returned nothing for that group' {
            # Addressing a group Graph will not answer for must not silently change the routing.
            Set-GroupLookup -Groups @()
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-dl' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
            )

            $null = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
        }

        It 'falls back to the option when the lookup itself fails' {
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'Graph unavailable' }
            $UserObj = New-TestUserObj -AddToGroups @(
                New-GroupOption -Label 'All Office' -Value 'group-dl' -GroupType 'Distribution List' -CalculatedGroupType 'distributionList'
            )

            $Result = Set-CIPPUser -UserObj $UserObj -APIName 'Edit User'

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-DistributionGroupMember' }
            $Result.Results | Should -Contain 'Success. Safiyah Seck has been added to All Office'
        }
    }
}

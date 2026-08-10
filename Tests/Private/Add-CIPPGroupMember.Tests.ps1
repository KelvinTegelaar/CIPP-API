# Pester tests for Add-CIPPGroupMember.
#
# This helper is the single choke point for "put a user in a group" across the product
# (Add User, user templates, the scheduler retry, CA exclusions, SharePoint members), and it
# has to route to two completely different APIs: Exchange Online for classic distribution
# lists and mail-enabled security groups, Graph for everything else. Graph physically cannot
# write membership to a classic DL, so a mis-routed add fails with
# "Cannot Update a mail-enabled security groups and or distribution list."
#
# These tests pin down the routing decision, the per-member success/failure accounting and
# the message shapes the frontend renders through CippApiResults.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Add-CIPPGroupMember.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Add-CIPPGroupMember.ps1 under Modules/' }

    function New-GraphBulkRequest { param($Requests, $tenantid, $scope, $asapp) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-NormalizedError { param($message) $message }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    # Real helper, not a stub: correlating Exchange bulk results back to operations is the thing
    # these tests are checking, so it has to be the production implementation.
    $ResolverPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Resolve-CippExoBulkResult.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ResolverPath) { throw 'Could not locate Resolve-CippExoBulkResult.ps1 under Modules/' }
    . $ResolverPath

    . $FunctionPath

    # Graph bulk responses for the lookup leg: one entry per requested user plus the group.
    function New-LookupResponse {
        param(
            [hashtable[]]$Users,
            [string]$GroupDisplayName = 'Contoso Group',
            [hashtable]$GroupBody
        )
        $Response = foreach ($User in $Users) {
            [pscustomobject]@{
                id     = "users-$($User.upn)"
                status = 200
                body   = [pscustomobject]@{ id = $User.id; userPrincipalName = $User.upn }
            }
        }
        $Body = if ($GroupBody) { [pscustomobject]$GroupBody } else { [pscustomobject]@{ id = 'group-guid'; displayName = $GroupDisplayName } }
        @($Response) + @([pscustomobject]@{ id = 'group'; status = 200; body = $Body })
    }

    # Graph bulk responses for the membership-add leg, keyed by user object id.
    function New-AddResponse {
        param([hashtable[]]$Results)
        foreach ($Result in $Results) {
            [pscustomobject]@{
                id     = $Result.id
                status = $Result.status
                body   = if ($Result.ContainsKey('message')) {
                    [pscustomobject]@{ error = [pscustomobject]@{ message = $Result.message } }
                } else { $null }
            }
        }
    }
}

Describe 'Add-CIPPGroupMember' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-ExoBulkRequest -MockWith { @() }
    }

    Context 'Routing to Exchange Online for mail-based groups' {
        # A classic DL and a mail-enabled security group are Exchange objects. Graph returns
        # "Cannot Update a mail-enabled security groups and or distribution list" for these, so
        # the add has to go through Add-DistributionGroupMember instead.
        It 'uses Add-DistributionGroupMember for a <GroupType>' -ForEach @(
            @{ GroupType = 'Distribution list' }
            @{ GroupType = 'Mail-Enabled Security' }
        ) {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' })
            }

            $Result = Add-CIPPGroupMember -GroupType $GroupType -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Add-DistributionGroupMember' -and
                $cmdletArray[0].CmdletInput.Parameters.Identity -eq 'group-guid' -and
                $cmdletArray[0].CmdletInput.Parameters.Member -eq 'sseck@contoso.com' -and
                $cmdletArray[0].CmdletInput.Parameters.BypassSecurityGroupManagerCheck -eq $true
            }
            # Only the lookup should have gone to Graph, never a members/$ref POST.
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
            $Result | Should -Be 'Successfully added user sseck@contoso.com to group Contoso Group.'
        }

        It 'routes on group type case-insensitively' {
            # Invoke-ListGroups emits 'Distribution List' (capital L) while callers and the
            # frontend template mapper use 'Distribution list'. Both must reach Exchange.
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' })
            }

            $null = Add-CIPPGroupMember -GroupType 'Distribution List' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly
        }

        It 'batches every member into a single Exchange bulk call' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(
                    @{ id = 'user-1'; upn = 'one@contoso.com' }
                    @{ id = 'user-2'; upn = 'two@contoso.com' }
                )
            }

            $Result = Add-CIPPGroupMember -GroupType 'Distribution list' -GroupId 'group-guid' -Member @('one@contoso.com', 'two@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter { $cmdletArray.Count -eq 2 }
            $Result | Should -Be 'Successfully added user one@contoso.com, two@contoso.com to group Contoso Group.'
        }

        It 'throws when Exchange reports an error for the batch' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' })
            }
            Mock -CommandName New-ExoBulkRequest -MockWith {
                @([pscustomobject]@{ target = 'sseck@contoso.com'; error = 'Cannot Update a mail-enabled security groups and or distribution list.' })
            }

            { Add-CIPPGroupMember -GroupType 'Distribution list' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*Cannot Update a mail-enabled security groups*'
        }

        It 'does not call Exchange when the user lookup returned nobody' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                @([pscustomobject]@{ id = 'group'; status = 200; body = [pscustomobject]@{ id = 'group-guid'; displayName = 'Contoso Group' } })
            }

            $null = Add-CIPPGroupMember -GroupType 'Distribution list' -GroupId 'group-guid' -Member @() -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }
    }

    Context 'Routing to Graph for directory groups' {
        It 'POSTs a members/$ref bind for a security group' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' })
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 204 })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $Result = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].method -eq 'POST' -and
                $Requests[0].url -eq '/groups/group-guid/members/$ref' -and
                $Requests[0].body.'@odata.id' -eq 'https://graph.microsoft.com/v1.0/directoryObjects/user-1'
            }
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            $Result | Should -Be 'Successfully added user sseck@contoso.com to group Contoso Group.'
        }

        It 'reports both the successes and the failures of a mixed batch without throwing' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(
                    @{ id = 'user-1'; upn = 'ok@contoso.com' }
                    @{ id = 'user-2'; upn = 'bad@contoso.com' }
                )
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(
                    @{ id = 'user-1'; status = 204 }
                    @{ id = 'user-2'; status = 400; message = 'One or more added object references already exist' }
                )
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $Result = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('ok@contoso.com', 'bad@contoso.com') -TenantFilter 'contoso.com'

            $Result | Should -Be 'Successfully added user ok@contoso.com to group Contoso Group. Failed to add bad@contoso.com (One or more added object references already exist).'
        }

        It 'throws when every member of the batch failed' {
            # New-CIPPUserTask relies on this throw to decide whether to schedule a retry.
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' })
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 400; message = 'Cannot Update a mail-enabled security groups and or distribution list.' })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            { Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*Cannot Update a mail-enabled security groups*'
        }

        It 'falls back to a status-based message when Graph returns no error body' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' })
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 503 })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            { Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*Request failed with status 503*'
        }

        It 'keeps only the first translation when Get-NormalizedError returns several' {
            Mock -CommandName Get-NormalizedError -MockWith { @('First translation', 'Second translation') }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(
                    @{ id = 'user-1'; upn = 'ok@contoso.com' }
                    @{ id = 'user-2'; upn = 'bad@contoso.com' }
                )
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(
                    @{ id = 'user-1'; status = 204 }
                    @{ id = 'user-2'; status = 400; message = 'ambiguous' }
                )
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $Result = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('ok@contoso.com', 'bad@contoso.com') -TenantFilter 'contoso.com'

            $Result | Should -Be 'Successfully added user ok@contoso.com to group Contoso Group. Failed to add bad@contoso.com (First translation).'
        }
    }

    Context 'Resolving the group type from the group itself' {
        # The caller-supplied group type comes from an autocomplete option and is missing on
        # template-stored groups and wrong whenever a group was converted after the option was
        # saved. Graph tells us what the group really is in the same lookup we already make, so
        # that answer wins; the caller's value is only a fallback for when the lookup says nothing.
        It 'sends a classic distribution list to Exchange even when the caller passed no type' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' }) -GroupBody @{
                    id = 'group-guid'; displayName = 'All Office'
                    groupTypes = @(); mailEnabled = $true; securityEnabled = $false
                }
            }

            $Result = Add-CIPPGroupMember -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Add-DistributionGroupMember'
            }
            $Result | Should -Be 'Successfully added user sseck@contoso.com to group All Office.'
        }

        It 'sends a mail-enabled security group to Exchange even when the caller passed no type' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' }) -GroupBody @{
                    id = 'group-guid'; displayName = 'SG-LIC-M365'
                    groupTypes = @(); mailEnabled = $true; securityEnabled = $true
                }
            }

            $null = Add-CIPPGroupMember -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly
        }

        It 'overrides a caller-supplied type that disagrees with the group' {
            # A stale template option saying 'Security' must not push a distribution list down the
            # Graph path, which is exactly how the reported failure happened.
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' }) -GroupBody @{
                    id = 'group-guid'; displayName = 'IEQ-Team'
                    groupTypes = @(); mailEnabled = $true; securityEnabled = $false
                }
            }

            $null = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly
        }

        It 'keeps a Microsoft 365 group on Graph even though it is mail-enabled' {
            # Unified groups are mail-enabled but Graph owns their membership.
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' }) -GroupBody @{
                    id = 'group-guid'; displayName = 'IEQ - ALL'
                    groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false
                }
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 204 })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $null = Add-CIPPGroupMember -GroupType 'Distribution list' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $Requests[0].method -eq 'POST' }
        }

        It 'keeps a plain security group on Graph' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' }) -GroupBody @{
                    id = 'group-guid'; displayName = 'All-Users'
                    groupTypes = @(); mailEnabled = $false; securityEnabled = $true
                }
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 204 })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $null = Add-CIPPGroupMember -GroupType 'Distribution list' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }

        It 'falls back to the caller-supplied type when the group lookup returned nothing usable' {
            # Addressing a group by mail rather than GUID, or a lookup that 404s, leaves us with
            # only what the caller told us.
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' }) -GroupBody @{
                    id = $null; displayName = $null
                }
            }

            $null = Add-CIPPGroupMember -GroupType 'Distribution list' -GroupId 'All Office' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.Parameters.Identity -eq 'All Office'
            }
        }
    }

    Context 'Member lookup' {
        It 'url-encodes guest accounts so the #EXT# segment survives the request' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'guest_partner.com#EXT#@contoso.onmicrosoft.com' })
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 204 })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $null = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('guest_partner.com#EXT#@contoso.onmicrosoft.com') -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].url -like 'users/*%23EXT%23*'
            }
        }

        It 'asks for the group alongside the members in one round trip' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' })
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 204 })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $null = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                ($Requests | Where-Object { $_.id -eq 'group' }).url -like 'groups/group-guid*'
            }
        }

        It 'falls back to the group id in messages when the display name lookup came back empty' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' }) -GroupBody @{ id = 'group-guid'; displayName = $null }
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 204 })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $Result = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            $Result | Should -Be 'Successfully added user sseck@contoso.com to group group-guid.'
        }

        It 'surfaces a lookup failure as a thrown, member-scoped message' {
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'Graph unavailable' }

            { Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*sseck@contoso.com*Graph unavailable*'
        }
    }

    Context 'Audit logging' {
        It 'logs the outcome against the tenant so it shows up in the CIPP log' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(@{ id = 'user-1'; upn = 'sseck@contoso.com' })
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(@{ id = 'user-1'; status = 204 })
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $null = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' -APIName 'Add Group Member'

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $API -eq 'Add Group Member' -and $tenant -eq 'contoso.com' -and $Sev -eq 'Info' -and
                $message -eq 'Successfully added user sseck@contoso.com to group Contoso Group.'
            }
        }

        It 'logs each Graph failure at Error severity' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-LookupResponse -Users @(
                    @{ id = 'user-1'; upn = 'ok@contoso.com' }
                    @{ id = 'user-2'; upn = 'bad@contoso.com' }
                )
            } -ParameterFilter { $Requests.method -contains 'GET' }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-AddResponse -Results @(
                    @{ id = 'user-1'; status = 204 }
                    @{ id = 'user-2'; status = 400; message = 'boom' }
                )
            } -ParameterFilter { $Requests.method -contains 'POST' }

            $null = Add-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('ok@contoso.com', 'bad@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $Sev -eq 'Error' -and $message -eq 'Failed to add member bad@contoso.com to group Contoso Group: boom'
            }
        }
    }
}

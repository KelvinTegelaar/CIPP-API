# Pester tests for Remove-CIPPGroups.
#
# The "remove from all groups" step of offboarding. It reads every group the user belongs to and
# decides, per group, whether the membership can be removed at all and which API can do it.
#
# The skip rules matter as much as the routing: a group that carries licences is deliberately left
# to the licence-removal step (pulling the user out here would strip the licence early), and
# dynamic or AD-synced groups cannot be edited from here at all. Getting a skip wrong either
# silently leaves an offboarded user in a group or removes a licence out from under them.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Remove-CIPPGroups.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPGroups.ps1 under Modules/' }

    function New-GraphBulkRequest { param($Requests, $tenantid, $scope, $asapp) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-NormalizedError { param($message) $message }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    # Real helper, not a stub: matching Exchange bulk results back to operations is what the
    # per-group reporting assertions below depend on.
    $ResolverPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Resolve-CippExoBulkResult.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ResolverPath) { throw 'Could not locate Resolve-CippExoBulkResult.ps1 under Modules/' }
    . $ResolverPath

    . $FunctionPath

    function New-Group {
        param(
            [string]$Id,
            [string]$DisplayName,
            [bool]$MailEnabled = $false,
            [string[]]$GroupTypes = @(),
            [object[]]$AssignedLicenses = @(),
            [bool]$OnPremisesSyncEnabled = $false,
            [string]$MembershipRule
        )
        [pscustomobject]@{
            id                    = $Id
            displayName           = $DisplayName
            mailEnabled           = $MailEnabled
            groupTypes            = $GroupTypes
            assignedLicenses      = $AssignedLicenses
            onPremisesSyncEnabled = $OnPremisesSyncEnabled
            membershipRule        = $MembershipRule
        }
    }

    # Data for the mocks lives in script scope: the mock scriptblocks run after these helpers return.
    function Set-Groups {
        param([object[]]$Groups, [switch]$NoMemberships)
        $script:AllGroups = @($Groups)
        $script:UserGroups = if ($NoMemberships) { @() } else { @($Groups | Select-Object -Property id) }
    }
    function Set-GraphRemovalResults { param([hashtable[]]$Results) $script:RemovalResults = @($Results) }
}

Describe 'Remove-CIPPGroups' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-ExoBulkRequest -MockWith { @() }
        Set-Groups -Groups @()
        Set-GraphRemovalResults -Results @()

        Mock -CommandName New-GraphBulkRequest -MockWith {
            @(
                [pscustomobject]@{ id = 'getUserID'; body = [pscustomobject]@{ id = 'user-guid' } }
                [pscustomobject]@{ id = 'getAllGroups'; body = [pscustomobject]@{ value = $script:AllGroups } }
                [pscustomobject]@{ id = 'getUserGroups'; body = [pscustomobject]@{ value = $script:UserGroups } }
            )
        } -ParameterFilter { $Requests.id -contains 'getAllGroups' }

        Mock -CommandName New-GraphBulkRequest -MockWith {
            foreach ($Result in $script:RemovalResults) {
                [pscustomobject]@{
                    id     = $Result.id
                    status = $Result.status
                    body   = [pscustomobject]@{ error = $Result.error }
                }
            }
        } -ParameterFilter { $Requests.id -notcontains 'getAllGroups' }
    }

    Context 'Routing each removal' {
        It 'removes a security group membership through Graph' {
            Set-Groups -Groups @(New-Group -Id 'group-sec' -DisplayName 'All-Users')
            Set-GraphRemovalResults -Results @(@{ id = 'removeFromGroup-group-sec'; status = 204 })

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].method -eq 'DELETE' -and
                $Requests[0].url -eq 'groups/group-sec/members/user-guid/$ref'
            }
            $Result | Should -Contain "Successfully removed sseck@contoso.com from group 'All-Users'"
        }

        It 'removes a Microsoft 365 group membership through Graph' {
            Set-Groups -Groups @(New-Group -Id 'group-m365' -DisplayName 'IEQ - ALL' -MailEnabled $true -GroupTypes @('Unified'))
            Set-GraphRemovalResults -Results @(@{ id = 'removeFromGroup-group-m365'; status = 204 })

            $null = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $Requests[0].method -eq 'DELETE' }
        }

        It 'removes a distribution list membership through Exchange, addressed by display name' {
            Set-Groups -Groups @(New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true)

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Remove-DistributionGroupMember' -and
                $cmdletArray[0].CmdletInput.Parameters.Identity -eq 'All Office' -and
                $cmdletArray[0].CmdletInput.Parameters.Member -eq 'user-guid' -and
                $cmdletArray[0].CmdletInput.Parameters.BypassSecurityGroupManagerCheck -eq $true
            }
            $Result | Should -Contain 'Successfully removed sseck@contoso.com from group All Office'
        }

        It 'splits a mixed membership set across both APIs' {
            Set-Groups -Groups @(
                New-Group -Id 'group-sec' -DisplayName 'All-Users'
                New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true
            )
            Set-GraphRemovalResults -Results @(@{ id = 'removeFromGroup-group-sec'; status = 204 })

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter { $cmdletArray.Count -eq 1 }
            $Result | Should -Contain "Successfully removed sseck@contoso.com from group 'All-Users'"
            $Result | Should -Contain 'Successfully removed sseck@contoso.com from group All Office'
        }
    }

    Context 'Memberships that are deliberately left alone' {
        It 'leaves a licence-bearing group to the licence removal step' {
            # Removing the user here would strip the licence before the offboarding job is ready.
            Set-Groups -Groups @(New-Group -Id 'group-lic' -DisplayName 'SG-LIC-M365' -AssignedLicenses @([pscustomobject]@{ skuId = 'sku-1' }))

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly -ParameterFilter { $Requests[0].method -eq 'DELETE' }
            $Result | Should -Contain "Skipping removal of sseck@contoso.com from group 'SG-LIC-M365' because it has assigned licenses. This group will be handled during the license removal step."
        }

        It 'reports a dynamic group as unremovable' {
            Set-Groups -Groups @(New-Group -Id 'group-dyn' -DisplayName 'Dynamic All' -MembershipRule 'user.department -eq "Sales"')

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly -ParameterFilter { $Requests[0].method -eq 'DELETE' }
            $Result | Should -Contain "Error: Could not remove sseck@contoso.com from group 'Dynamic All' because it is a Dynamic Group."
        }

        It 'reports an AD-synced group as unremovable' {
            Set-Groups -Groups @(New-Group -Id 'group-ad' -DisplayName 'Synced Group' -OnPremisesSyncEnabled $true)

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly -ParameterFilter { $Requests[0].method -eq 'DELETE' }
            $Result | Should -Contain "Error: Could not remove sseck@contoso.com from group 'Synced Group' because it is synced with Active Directory."
        }

        It 'still removes the removable groups alongside the skipped ones' {
            Set-Groups -Groups @(
                New-Group -Id 'group-lic' -DisplayName 'SG-LIC-M365' -AssignedLicenses @([pscustomobject]@{ skuId = 'sku-1' })
                New-Group -Id 'group-dyn' -DisplayName 'Dynamic All' -MembershipRule 'user.department -eq "Sales"'
                New-Group -Id 'group-sec' -DisplayName 'All-Users'
            )
            Set-GraphRemovalResults -Results @(@{ id = 'removeFromGroup-group-sec'; status = 204 })

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests.Count -eq 1 -and $Requests[0].url -like '*group-sec*'
            }
            $Result | Should -Contain "Successfully removed sseck@contoso.com from group 'All-Users'"
        }

        It 'returns early when the user belongs to no groups' {
            Set-Groups -Groups @(New-Group -Id 'group-sec' -DisplayName 'All-Users') -NoMemberships

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            $Result | Should -Be 'sseck@contoso.com is not a member of any groups.'
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }
    }

    Context 'Failures' {
        It 'reports a Graph removal that came back non-2xx' {
            Set-Groups -Groups @(New-Group -Id 'group-sec' -DisplayName 'All-Users')
            Set-GraphRemovalResults -Results @(@{ id = 'removeFromGroup-group-sec'; status = 403; error = 'Insufficient privileges' })

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            $Result | Should -Contain "Could not remove sseck@contoso.com from group 'All-Users': Insufficient privileges. This is likely because it's a Dynamic Group or synced with Active Directory"
        }

        It 'reports an Exchange removal error against the group it belongs to' {
            # Offboarding removes one user from many groups at once, so an error that only names
            # the user tells the operator nothing about which removal actually failed.
            Set-Groups -Groups @(New-Group -Id 'group-dl' -DisplayName 'All Office' -MailEnabled $true)
            Mock -CommandName New-ExoBulkRequest -MockWith {
                @([pscustomobject]@{ target = 'user-guid'; error = 'The user is not a member of the group.' })
            }

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            $Result | Should -Contain 'Could not remove sseck@contoso.com from All Office: The user is not a member of the group.'
        }

        It 'does not claim success for the other groups when one Exchange removal fails' {
            # Every entry in an offboarding batch shares the same target (the user), so a failure
            # used to be attributed to none of them and all were reported as removed.
            Set-Groups -Groups @(
                New-Group -Id 'group-dl-a' -DisplayName 'All Office' -MailEnabled $true
                New-Group -Id 'group-dl-b' -DisplayName 'IEQ-Team' -MailEnabled $true
            )
            Mock -CommandName New-ExoBulkRequest -MockWith {
                param($cmdletArray)
                # Fail the first operation only, echoing its guid back the way Exchange does.
                @([pscustomobject]@{
                        target        = 'user-guid'
                        error         = 'The user is not a member of the group.'
                        OperationGuid = $cmdletArray[0].OperationGuid
                    })
            }

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            $Result | Should -Contain 'Could not remove sseck@contoso.com from All Office: The user is not a member of the group.'
            $Result | Should -Contain 'Successfully removed sseck@contoso.com from group IEQ-Team'
        }

        It 'returns a preparation error when the membership lookup throws' {
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'Graph unavailable' } -ParameterFilter { $Requests.id -contains 'getAllGroups' }

            $Result = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            $Result | Should -BeLike 'Error preparing bulk group removal requests:*Graph unavailable*'
        }
    }

    Context 'Resolving the user' {
        It 'looks the user id up from the username when it was not supplied' {
            Set-Groups -Groups @(New-Group -Id 'group-sec' -DisplayName 'All-Users')
            Set-GraphRemovalResults -Results @(@{ id = 'removeFromGroup-group-sec'; status = 204 })

            $null = Remove-CIPPGroups -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                ($Requests | Where-Object { $_.id -eq 'getUserID' }).url -like 'users/sseck@contoso.com*'
            }
        }

        It 'skips the lookup when the caller already knows the user id' {
            Set-Groups -Groups @(New-Group -Id 'group-sec' -DisplayName 'All-Users')
            Set-GraphRemovalResults -Results @(@{ id = 'removeFromGroup-group-sec'; status = 204 })

            $null = Remove-CIPPGroups -Username 'sseck@contoso.com' -UserID 'known-guid' -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests.id -notcontains 'getUserID' -and
                ($Requests | Where-Object { $_.id -eq 'getUserGroups' }).url -like 'users/known-guid/*'
            }
        }
    }
}

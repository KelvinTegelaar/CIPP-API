# Pester tests for Remove-CIPPGroupMember.
#
# The mirror of Add-CIPPGroupMember: same two-API split (Exchange for distribution lists and
# mail-enabled security groups, Graph for directory groups), same per-member accounting.
# Removals are driven from the Edit User page and from group management, so a mis-routed
# removal silently leaves the user in the group.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Remove-CIPPGroupMember.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPGroupMember.ps1 under Modules/' }

    function New-GraphBulkRequest { param($Requests, $tenantid, $scope, $asapp) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $UseSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-NormalizedError { param($message) $message }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Resolve-CIPPDirectoryId { param($Identity, $TenantFilter) }

    # Real helper, not a stub: correlating Exchange bulk results back to operations is the thing
    # these tests are checking, so it has to be the production implementation.
    $ResolverPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Resolve-CippExoBulkResult.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ResolverPath) { throw 'Could not locate Resolve-CippExoBulkResult.ps1 under Modules/' }
    . $ResolverPath

    # The resolver delegates error-text extraction to this pure helper; use the real one too.
    $ErrorTextPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CippExoErrorText.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ErrorTextPath) { throw 'Could not locate Get-CippExoErrorText.ps1 under Modules/' }
    . $ErrorTextPath

    $GroupTypePath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPGroupType.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $GroupTypePath) { throw 'Could not locate Get-CIPPGroupType.ps1 under Modules/' }
    . $GroupTypePath

    . $FunctionPath

    function New-ResolvedDirectoryObject {
        param($InputIdentity, $Id, $Upn, $DisplayName, [string]$Type = 'User', [bool]$Resolved = $true)
        $Label = $DisplayName ?? $Upn ?? $InputIdentity
        [pscustomobject]@{
            Input             = $InputIdentity
            Id                = $Id
            UserPrincipalName = $Upn
            DisplayName       = $DisplayName
            Mail              = $null
            MailNickname      = $null
            ODataType         = "#microsoft.graph.$($Type.ToLowerInvariant())"
            Type              = $Type
            ExchangeIdentity  = $Upn ?? $Id
            Label             = $Label
            Resolved          = $Resolved
        }
    }

    function New-RemoveResponse {
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

Describe 'Remove-CIPPGroupMember' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-ExoBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'group-guid'; displayName = 'Contoso Group' }
        }
        Mock -CommandName New-ExoRequest -MockWith { throw 'Distribution group not found' }
        Mock -CommandName Resolve-CIPPDirectoryId -MockWith {
            param($Identity, $TenantFilter)
            foreach ($raw in @($Identity)) {
                $id = switch -Wildcard ($raw) {
                    'sseck@*' { 'user-1' }
                    'one@*' { 'user-1' }
                    'two@*' { 'user-2' }
                    'ok@*' { 'user-1' }
                    'bad@*' { 'user-2' }
                    '*#EXT#*' { 'user-1' }
                    default { $raw }
                }
                $upn = if ($raw -match '@' -or $raw -like '*#EXT#*') { $raw } else { $null }
                New-ResolvedDirectoryObject -InputIdentity $raw -Id $id -Upn $upn
            }
        }
    }

    Context 'Routing to Exchange Online for mail-based groups' {
        It 'uses Remove-DistributionGroupMember for a <GroupType>' -ForEach @(
            @{ GroupType = 'Distribution list' }
            @{ GroupType = 'Mail-Enabled Security' }
        ) {
            $Result = Remove-CIPPGroupMember -GroupType $GroupType -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Remove-DistributionGroupMember' -and
                $cmdletArray[0].CmdletInput.Parameters.Identity -eq 'group-guid' -and
                $cmdletArray[0].CmdletInput.Parameters.Member -eq 'sseck@contoso.com' -and
                $cmdletArray[0].CmdletInput.Parameters.BypassSecurityGroupManagerCheck -eq $true
            }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            $Result | Should -Be 'Successfully removed sseck@contoso.com from group Contoso Group.'
        }

        It 'routes on group type case-insensitively' {
            $null = Remove-CIPPGroupMember -GroupType 'Distribution List' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }

        It 'throws when Exchange reports an error for the batch' {
            Mock -CommandName New-ExoBulkRequest -MockWith {
                @([pscustomobject]@{ target = 'sseck@contoso.com'; error = 'The user is not a member of the group.' })
            }

            { Remove-CIPPGroupMember -GroupType 'Distribution list' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*not a member of the group*'
        }
    }

    Context 'Routing to Graph for directory groups' {
        It 'DELETEs the members/$ref for a security group' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-RemoveResponse -Results @(@{ id = 'user-1'; status = 204 })
            }

            $Result = Remove-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].method -eq 'DELETE' -and
                $Requests[0].url -eq '/groups/group-guid/members/user-1/$ref'
            }
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            $Result | Should -Be 'Successfully removed sseck@contoso.com from group Contoso Group.'
        }

        It 'reports both the successes and the failures of a mixed batch without throwing' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-RemoveResponse -Results @(
                    @{ id = 'user-1'; status = 204 }
                    @{ id = 'user-2'; status = 404; message = 'Resource not found' }
                )
            }

            $Result = Remove-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('ok@contoso.com', 'bad@contoso.com') -TenantFilter 'contoso.com'

            $Result | Should -Be 'Successfully removed ok@contoso.com from group Contoso Group. Failed to remove bad@contoso.com (Resource not found).'
        }

        It 'throws when every member of the batch failed' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-RemoveResponse -Results @(@{ id = 'user-1'; status = 400; message = 'Cannot Update a mail-enabled security groups and or distribution list.' })
            }

            { Remove-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*Cannot Update a mail-enabled security groups*'
        }
    }

    Context 'Member lookup' {
        It 'passes guest identities through to Resolve-CIPPDirectoryId' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-RemoveResponse -Results @(@{ id = 'user-1'; status = 204 })
            }

            $Guest = 'guest_partner.com#EXT#@contoso.onmicrosoft.com'
            $null = Remove-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @($Guest) -TenantFilter 'contoso.com'

            Should -Invoke Resolve-CIPPDirectoryId -Times 1 -Exactly -ParameterFilter {
                @($Identity) -contains $Guest
            }
        }

        It 'surfaces a lookup failure as a thrown, member-scoped message' {
            Mock -CommandName Resolve-CIPPDirectoryId -MockWith { throw 'Graph unavailable' }

            { Remove-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*sseck@contoso.com*Graph unavailable*'
        }
    }

    Context 'Audit logging' {
        It 'logs the outcome against the tenant so it shows up in the CIPP log' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-RemoveResponse -Results @(@{ id = 'user-1'; status = 204 })
            }

            $null = Remove-CIPPGroupMember -GroupType 'Security' -GroupId 'group-guid' -Member @('sseck@contoso.com') -TenantFilter 'contoso.com' -APIName 'Remove Group Member'

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $API -eq 'Remove Group Member' -and $tenant -eq 'contoso.com' -and $Sev -eq 'Info' -and
                $message -eq 'Successfully removed sseck@contoso.com from group Contoso Group.'
            }
        }
    }
}

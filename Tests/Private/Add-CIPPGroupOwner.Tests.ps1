# Pester tests for Add-CIPPGroupOwner.
#
# Owners on Graph-backed groups are a POST to owners/$ref. Owners on classic DLs and
# mail-enabled security groups are a wholesale ManagedBy rewrite via Set-DistributionGroup
# (there is no Add-DistributionGroupOwner). Identities are resolved to Graph ids first so
# compare/write matches ListGroups and EditGroup.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Add-CIPPGroupOwner.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Add-CIPPGroupOwner.ps1 under Modules/' }

    function New-GraphBulkRequest { param($Requests, $tenantid, $scope, $asapp) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $UseSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-NormalizedError { param($message) $message }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Resolve-CIPPDirectoryId { param($Identity, $TenantFilter) }

    $ResolverPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Resolve-CippExoBulkResult.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ResolverPath) { throw 'Could not locate Resolve-CippExoBulkResult.ps1 under Modules/' }
    . $ResolverPath

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

    function New-OwnerGraphResponse {
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

Describe 'Add-CIPPGroupOwner' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-ExoBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-ExoRequest -MockWith { throw 'Distribution group not found' }
        Mock -CommandName Resolve-CIPPDirectoryId -MockWith {
            param($Identity, $TenantFilter)
            foreach ($raw in @($Identity)) {
                if ($raw -eq 'missing@contoso.com') {
                    New-ResolvedDirectoryObject -InputIdentity $raw -Id $null -Upn $raw -Resolved $false
                    continue
                }
                $id = switch -Wildcard ($raw) {
                    'existing@*' { 'existing-guid' }
                    'boss@*' { 'boss-guid' }
                    'keep@*' { 'keep-guid' }
                    'existing-guid' { 'existing-guid' }
                    'boss-guid' { 'boss-guid' }
                    'keep-guid' { 'keep-guid' }
                    default { $raw }
                }
                $upn = if ($raw -match '@') { $raw } else {
                    ($id -replace '-guid$', '@contoso.com')
                }
                New-ResolvedDirectoryObject -InputIdentity $raw -Id $id -Upn $upn
            }
        }
    }

    Context 'Routing to Exchange for mail-based groups' {
        BeforeEach {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{
                    id              = 'group-guid'
                    displayName     = 'Contoso DL'
                    groupTypes      = @()
                    mailEnabled     = $true
                    securityEnabled = $false
                }
            }
            Mock -CommandName New-ExoRequest -MockWith {
                [pscustomobject]@{ ManagedBy = @('existing@contoso.com') }
            }
        }

        It 'rewrites ManagedBy with Graph ids when adding an owner to a distribution list' {
            $Result = Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('boss@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Set = $cmdletArray[0]
                $Set.CmdletInput.CmdletName -eq 'Set-DistributionGroup' -and
                $Set.CmdletInput.Parameters.Identity -eq 'group-guid' -and
                $Set.CmdletInput.Parameters.ManagedBy -contains 'existing-guid' -and
                $Set.CmdletInput.Parameters.ManagedBy -contains 'boss-guid' -and
                $Set.CmdletInput.Parameters.BypassSecurityGroupManagerCheck -eq $true
            }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            $Result | Should -BeLike 'Successfully added owner*boss@contoso.com*Contoso DL*'
        }

        It 'rewrites ManagedBy for a mail-enabled security group' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{
                    id              = 'group-guid'
                    displayName     = 'Contoso MES'
                    groupTypes      = @()
                    mailEnabled     = $true
                    securityEnabled = $true
                }
            }

            $null = Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('boss@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Set-DistributionGroup' -and
                $cmdletArray[0].CmdletInput.Parameters.BypassSecurityGroupManagerCheck -eq $true
            }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }

        It 'does not call Exchange when the owner is already ManagedBy' {
            { Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('existing@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*already an owner*'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }

        It 'does not call Exchange when the owner cannot be resolved' {
            { Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('missing@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*user not found*'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }

        It 'throws when Exchange reports an error for the ManagedBy rewrite' {
            Mock -CommandName New-ExoBulkRequest -MockWith {
                @([pscustomobject]@{
                        error         = 'The executing user is not in the current organization'
                        OperationGuid = $cmdletArray[0].OperationGuid
                    })
            }

            { Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('boss@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*not in the current organization*'
        }
    }

    Context 'Routing to Graph for directory groups' {
        BeforeEach {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{
                    id              = 'group-guid'
                    displayName     = 'Contoso Security'
                    groupTypes      = @()
                    mailEnabled     = $false
                    securityEnabled = $true
                }
            }
        }

        It 'POSTs an owners/$ref bind for a security group' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-OwnerGraphResponse -Results @(@{ id = 'boss-guid'; status = 204 })
            }

            $Result = Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('boss@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].method -eq 'POST' -and
                $Requests[0].url -eq '/groups/group-guid/owners/$ref' -and
                $Requests[0].body.'@odata.id' -eq 'https://graph.microsoft.com/v1.0/directoryObjects/boss-guid'
            }
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            $Result | Should -BeLike 'Successfully added owner*boss@contoso.com*Contoso Security*'
        }

        It 'POSTs an owners/$ref bind for a Microsoft 365 group' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{
                    id              = 'group-guid'
                    displayName     = 'Contoso M365'
                    groupTypes      = @('Unified')
                    mailEnabled     = $true
                    securityEnabled = $false
                }
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-OwnerGraphResponse -Results @(@{ id = 'boss-guid'; status = 204 })
            }

            $null = Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('boss@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }

        It 'throws when Graph returns a non-2xx for every owner' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-OwnerGraphResponse -Results @(@{ id = 'boss-guid'; status = 400; message = 'One or more added object references already exist' })
            }

            { Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('boss@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*already exist*'
        }

        It 'does not call Graph when the owner cannot be resolved' {
            { Add-CIPPGroupOwner -GroupId 'group-guid' -Owner @('missing@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*user not found*'

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }
    }
}

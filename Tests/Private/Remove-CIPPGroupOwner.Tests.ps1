# Pester tests for Remove-CIPPGroupOwner.
#
# Mirror of Add-CIPPGroupOwner: Graph DELETE of owners/$ref for directory groups, ManagedBy
# rewrite (list without them) for classic DLs and mail-enabled security groups.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Remove-CIPPGroupOwner.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPGroupOwner.ps1 under Modules/' }

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

Describe 'Remove-CIPPGroupOwner' {
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
                    'keep@*' { 'keep-guid' }
                    'drop@*' { 'drop-guid' }
                    'boss@*' { 'boss-guid' }
                    'keep-guid' { 'keep-guid' }
                    'drop-guid' { 'drop-guid' }
                    'boss-guid' { 'boss-guid' }
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
                [pscustomobject]@{ ManagedBy = @('keep@contoso.com', 'drop@contoso.com') }
            }
        }

        It 'drops the removed owner out of the rewritten ManagedBy list' {
            $Result = Remove-CIPPGroupOwner -GroupId 'group-guid' -Owner @('drop@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Set = $cmdletArray[0]
                $Set.CmdletInput.CmdletName -eq 'Set-DistributionGroup' -and
                $Set.CmdletInput.Parameters.ManagedBy -contains 'keep-guid' -and
                $Set.CmdletInput.Parameters.ManagedBy -notcontains 'drop-guid' -and
                $Set.CmdletInput.Parameters.BypassSecurityGroupManagerCheck -eq $true
            }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            $Result | Should -BeLike 'Successfully removed owner*drop@contoso.com*Contoso DL*'
        }

        It 'does not call Exchange when the owner is not in ManagedBy' {
            { Remove-CIPPGroupOwner -GroupId 'group-guid' -Owner @('boss@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*not an owner*'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }

        It 'does not call Exchange when the owner cannot be resolved' {
            { Remove-CIPPGroupOwner -GroupId 'group-guid' -Owner @('missing@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*user not found*'

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
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

        It 'DELETEs the owners/$ref for a security group' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-OwnerGraphResponse -Results @(@{ id = 'drop-guid'; status = 204 })
            }

            $Result = Remove-CIPPGroupOwner -GroupId 'group-guid' -Owner @('drop@contoso.com') -TenantFilter 'contoso.com'

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].method -eq 'DELETE' -and
                $Requests[0].url -eq '/groups/group-guid/owners/drop-guid/$ref'
            }
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            $Result | Should -BeLike 'Successfully removed owner*drop@contoso.com*Contoso Security*'
        }

        It 'throws when Graph returns a non-2xx for every owner' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-OwnerGraphResponse -Results @(@{ id = 'drop-guid'; status = 404; message = 'Resource not found' })
            }

            { Remove-CIPPGroupOwner -GroupId 'group-guid' -Owner @('drop@contoso.com') -TenantFilter 'contoso.com' } |
                Should -Throw -ExpectedMessage '*Resource not found*'
        }
    }
}

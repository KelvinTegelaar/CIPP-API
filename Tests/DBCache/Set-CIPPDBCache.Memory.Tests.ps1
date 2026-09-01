# Pester tests for the DBCache collectors reworked to bound memory use.
#
# These cover the behaviour that had to survive the rework rather than the memory profile itself:
# the rows handed to Add-CIPPDbItem must be the same rows, with the same properties in the same
# order, and the "write nothing" paths must still write nothing.
#
# Add-CIPPDbItem is a recording stub rather than a Pester mock: the collectors now pipe into it,
# and asserting on the captured pipeline items is what actually proves the streaming rewrites
# still emit every row.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $CacheRoot = Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache'

    function Get-CollectorPath {
        param([string]$Name)
        $Path = Join-Path $CacheRoot "$Name.ps1"
        if (-not (Test-Path $Path)) { throw "Could not locate $Name.ps1 under $CacheRoot" }
        return $Path
    }

    # --- dependency stubs -------------------------------------------------------------------
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $Sev2, $LogData) }
    function Get-CippException { param($Exception) }
    function New-GraphGetRequest { param($uri, $tenantid, $scope, $AsApp, [bool]$noPagination, $Caller, [switch]$ComplexFilter, [switch]$Stream, $Headers) }
    # PowerShell parameter names are case-insensitive, so a single $AsApp binds both the -asapp
    # and -AsApp spellings the collectors use.
    function New-GraphBulkRequest { param($Requests, $tenantid, $AsApp, $scope) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox, $Select, $ReturnWithCommand) }
    function New-ExoRequest { param($cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox, $tenantid, $NoAuthCheck, [switch]$Compliance, $ApiVersion, $ModuleVersion, [switch]$AsApp, [switch]$UseCertificate) }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPSPOSite { param($TenantFilter, $SiteUrl) @() }
    function Get-SharePointAdminLink { param($Public, $tenantFilter) [PSCustomObject]@{ AdminUrl = 'https://contoso-admin.sharepoint.com'; SharePointUrl = 'https://contoso.sharepoint.com' } }
    function Get-CIPPSPOAdminListData { param($TenantFilter, $AdminUrl, $Type) @() }
    function Update-CippQueueEntry { param($RowKey, $TotalTasks, [switch]$IncrementTotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject, $InputObjectGuid, [switch]$CallerIsQueueTrigger) }
    function Get-ExoOnlineStringBytes { param($SizeString) }

    # Recording stand-in for the real writer. Mirrors its parameter surface so binding behaves the
    # same (pipeline + -Data alias), and records one entry per invocation with the rows it received.
    function Add-CIPPDbItem {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$TenantFilter,
            [Parameter(Mandatory)][string]$Type,
            [Parameter(Mandatory, ValueFromPipeline)][Alias('Data')][AllowNull()][AllowEmptyCollection()]$InputObject,
            [switch]$Count,
            [switch]$AddCount,
            [switch]$Append,
            [int]$SkewMarginMinutes = 5
        )
        begin {
            # EndRan is what proves the count row / orphan cleanup would have happened: collectors
            # that open their writer up front still must not call End() on an empty result.
            $Entry = [pscustomobject]@{
                Type     = $Type
                Tenant   = $TenantFilter
                AddCount = $AddCount.IsPresent
                Rows     = [System.Collections.Generic.List[object]]::new()
                EndRan   = $false
            }
            $script:DbWrites.Add($Entry)
        }
        process {
            foreach ($Item in @($InputObject)) {
                if ($null -ne $Item) { $Entry.Rows.Add($Item) }
            }
        }
        end { $Entry.EndRan = $true }
    }

    function New-BulkReportResponse {
        param($SharePointRows = @(), $OneDriveRows = @(), $AllSites = @(), $TeamRows = @())
        @(
            [pscustomobject]@{ id = 'sharePointUsage'; status = 200; body = [pscustomobject]@{ value = $SharePointRows } }
            [pscustomobject]@{ id = 'oneDriveUsage'; status = 200; body = [pscustomobject]@{ value = $OneDriveRows } }
            [pscustomobject]@{ id = 'listAllSites'; status = 200; body = [pscustomobject]@{ value = $AllSites } }
            [pscustomobject]@{ id = 'teamsActivity'; status = 200; body = [pscustomobject]@{ value = $TeamRows } }
        )
    }

    # Real helper, not a stub: it is pure logic with no external calls, and the mailbox collector's
    # AutoExpandingArchive/AutoExpandingArchiveScope columns are part of the row shape under test.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPAutoExpandingArchiveState.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-SPOUsageRootWebTemplate.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharePointSiteUsageRows.ps1')

    . (Get-CollectorPath 'Set-CIPPDBCacheGroups')
    . (Get-CollectorPath 'Set-CIPPDBCacheTeams')
    . (Get-CollectorPath 'Set-CIPPDBCacheSiteActivity')
    . (Get-CollectorPath 'Set-CIPPDBCacheSharePointSiteUsage')
    . (Get-CollectorPath 'Set-CIPPDBCacheMailboxes')
    . (Get-CollectorPath 'Set-CIPPDBCacheUserRegistrationDetails')
    . (Get-CollectorPath 'Set-CIPPDBCacheCopilotUsageUserDetail')
}

Describe 'DBCache collectors reworked for bounded memory' {

    BeforeEach {
        $script:DbWrites = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'boom' } }
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Update-CippQueueEntry -MockWith { }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.com' } }
    }

    Context 'Set-CIPPDBCacheGroups' {
        It 'attaches each group its own members instead of scanning the whole response per group' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @(
                    [pscustomobject]@{ id = 'g1'; displayName = 'One'; mail = 'one@contoso.com'; groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false; resourceProvisioningOptions = @('Team') }
                    [pscustomobject]@{ id = 'g2'; displayName = 'Two'; mail = 'two@contoso.com'; groupTypes = @(); mailEnabled = $false; securityEnabled = $true; resourceProvisioningOptions = @() }
                )
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                @(
                    [pscustomobject]@{ id = 'g2'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u2' }) } }
                    [pscustomobject]@{ id = 'g1'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u1a' }, [pscustomobject]@{ id = 'u1b' }) } }
                )
            }

            Set-CIPPDBCacheGroups -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $script:DbWrites.Count | Should -Be 1
            $Rows = $script:DbWrites[0].Rows
            $Rows.Count | Should -Be 2
            $script:DbWrites[0].EndRan | Should -BeTrue
            # Members are matched by id, not by position - the bulk response above is deliberately
            # in a different order than the group list.
            ($Rows | Where-Object id -EQ 'g1').members.id | Should -Be @('u1a', 'u1b')
            ($Rows | Where-Object id -EQ 'g2').members.id | Should -Be @('u2')
        }

        It 'emits the computed properties in the documented order' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @([pscustomobject]@{ id = 'g1'; displayName = 'One'; mail = 'one@contoso.com'; groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false; resourceProvisioningOptions = @('Team') })
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                @([pscustomobject]@{ id = 'g1'; body = [pscustomobject]@{ value = @() } })
            }

            Set-CIPPDBCacheGroups -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $Row = $script:DbWrites[0].Rows[0]
            $Added = @($Row.PSObject.Properties.Name) | Select-Object -Last 6
            $Added | Should -Be @('members', 'primDomain', 'teamsEnabled', 'dynamicGroupBool', 'groupType', 'calculatedGroupType')
            $Row.groupType | Should -Be 'Microsoft 365'
            $Row.calculatedGroupType | Should -Be 'm365'
            $Row.primDomain | Should -Be 'contoso.com'
            $Row.teamsEnabled | Should -BeTrue
        }

        It 'omits the members property entirely when no member lookup ran' {
            # No group carries an id, so no member requests are built - the pre-existing no-members shape.
            Mock -CommandName New-GraphGetRequest -MockWith {
                @([pscustomobject]@{ id = $null; displayName = 'One'; mail = 'one@contoso.com'; groupTypes = @(); mailEnabled = $true; securityEnabled = $true; resourceProvisioningOptions = @() })
            }
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'should not be called' }

            Set-CIPPDBCacheGroups -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $Row = $script:DbWrites[0].Rows[0]
            $Row.PSObject.Properties.Name | Should -Not -Contain 'members'
            $Row.groupType | Should -Be 'Mail-Enabled Security'
        }

        It 'still emits the members property when the member lookup returns nothing' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @([pscustomobject]@{ id = 'g1'; displayName = 'One'; mail = 'one@contoso.com'; groupTypes = @(); mailEnabled = $true; securityEnabled = $true; resourceProvisioningOptions = @() })
            }
            Mock -CommandName New-GraphBulkRequest -MockWith { @() }

            Set-CIPPDBCacheGroups -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $script:DbWrites[0].Rows[0].PSObject.Properties.Name | Should -Contain 'members'
        }

        It 'fetches members in batches of 50 and uses a single writer end block' {
            $Groups = 1..105 | ForEach-Object {
                [pscustomobject]@{
                    id                          = ('g{0:D3}' -f $_)
                    displayName                 = "Group $_"
                    mail                        = "g$_@contoso.com"
                    groupTypes                  = @()
                    mailEnabled                 = $true
                    securityEnabled             = $true
                    resourceProvisioningOptions = @()
                }
            }
            Mock -CommandName New-GraphGetRequest -MockWith { $Groups }
            $script:BulkCallCount = 0
            Mock -CommandName New-GraphBulkRequest -MockWith {
                $script:BulkCallCount++
                foreach ($Request in $Requests) {
                    [pscustomobject]@{ id = $Request.id; body = [pscustomobject]@{ value = @() } }
                }
            }

            Set-CIPPDBCacheGroups -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $script:BulkCallCount | Should -Be 3
            $script:DbWrites.Count | Should -Be 1
            $script:DbWrites[0].Rows.Count | Should -Be 105
            $script:DbWrites[0].EndRan | Should -BeTrue
        }

        It 'writes nothing when the stream is empty, preserving the previous cache' {
            Mock -CommandName New-GraphGetRequest -MockWith { @() }
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'should not be called' }

            Set-CIPPDBCacheGroups -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            $script:DbWrites.Count | Should -Be 1
            $script:DbWrites[0].Rows.Count | Should -Be 0
            $script:DbWrites[0].EndRan | Should -BeFalse
        }

        It 'skips member lookup for dynamic groups and omits the members property' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @(
                    [pscustomobject]@{ id = 'g-static'; displayName = 'Static'; mail = 'static@contoso.com'; groupTypes = @(); mailEnabled = $true; securityEnabled = $true; resourceProvisioningOptions = @() }
                    [pscustomobject]@{ id = 'g-dynamic'; displayName = 'Dynamic'; mail = 'dynamic@contoso.com'; groupTypes = @('DynamicMembership'); mailEnabled = $false; securityEnabled = $true; resourceProvisioningOptions = @(); membershipRule = '(user.department -eq "Sales")' }
                )
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                param($Requests)
                $Requests.id | Should -Be @('g-static')
                @([pscustomobject]@{ id = 'g-static'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u1'; userPrincipalName = 'u1@contoso.com' }) } })
            }

            Set-CIPPDBCacheGroups -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $Rows = $script:DbWrites[0].Rows
            ($Rows | Where-Object id -EQ 'g-static').members.userPrincipalName | Should -Be @('u1@contoso.com')
            ($Rows | Where-Object id -EQ 'g-dynamic').PSObject.Properties.Name | Should -Not -Contain 'members'
            ($Rows | Where-Object id -EQ 'g-dynamic').dynamicGroupBool | Should -BeTrue
        }
    }

    Context 'Set-CIPPDBCacheTeams' {
        It 'streams every team into the writer' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @(
                    [pscustomobject]@{ id = 't2'; displayName = 'Zebra' }
                    [pscustomobject]@{ id = 't1'; displayName = 'Alpha' }
                )
            }

            Set-CIPPDBCacheTeams -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $script:DbWrites.Count | Should -Be 1
            $script:DbWrites[0].Rows.id | Should -Be @('t2', 't1')
            $script:DbWrites[0].AddCount | Should -BeTrue
        }
    }

    Context 'Set-CIPPDBCacheSharePointSiteUsage' {
        BeforeEach {
            Mock -CommandName Get-CIPPSPOSite -MockWith { @() }
            Mock -CommandName Get-CIPPSPOAdminListData -MockWith {
                @(
                    [pscustomobject]@{
                        Title           = 'Site One'
                        SiteUrl         = 'https://c/s1'
                        SiteId          = '{site-1}'
                        StorageUsed       = [int64]1073741824
                        StorageQuota      = [int64]1024
                        StorageQuotaBytes = [int64](1024 * 1MB)
                        NumOfFiles        = [int64]10
                        TemplateName    = 'STS#3'
                        SiteOwnerEmail  = 'owner1@contoso.com'
                        SiteOwnerName   = 'Owner One'
                        LastActivityOn  = '2026-01-01'
                        TimeCreated     = '2020-01-01'
                    }
                    [pscustomobject]@{
                        Title           = 'Site Two'
                        SiteUrl         = 'https://c/s2'
                        SiteId          = '{site-2}'
                        StorageUsed       = [int64]2048
                        StorageQuota      = [int64]2048
                        StorageQuotaBytes = [int64](2048 * 1MB)
                        NumOfFiles        = [int64]2
                        TemplateName    = 'GROUP#0'
                        SiteOwnerEmail  = 'owner2@contoso.com'
                        SiteOwnerName   = 'Owner Two'
                        LastActivityOn  = '2026-02-01'
                        TimeCreated     = '2021-01-01'
                    }
                )
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                if ($Requests[0].id -eq 'listAllSites') {
                    return @(
                        [pscustomobject]@{ id = 'listAllSites'; body = [pscustomobject]@{ value = @(
                                    [pscustomobject]@{ id = 's1'; displayName = 'Site One'; webUrl = 'https://c/s1'; isPersonalSite = $false; sharepointIds = [pscustomobject]@{ siteId = 'site-1'; webId = 'web-1' } }
                                    [pscustomobject]@{ id = 's2'; displayName = 'Site Two'; webUrl = 'https://c/s2'; isPersonalSite = $false; sharepointIds = [pscustomobject]@{ siteId = 'site-2'; webId = 'web-2' } }
                                ) } }
                    )
                }
                return @(
                    [pscustomobject]@{ body = [pscustomobject]@{ value = @(
                                [pscustomobject]@{ id = 'list-2'; list = [pscustomobject]@{ template = 'DocumentLibrary' }; parentReference = [pscustomobject]@{ siteId = 'contoso.sharepoint.com,site-2,web-2' } }
                                [pscustomobject]@{ id = 'list-1'; list = [pscustomobject]@{ template = 'DocumentLibrary' }; parentReference = [pscustomobject]@{ siteId = 'contoso.sharepoint.com,site-1,web-1' } }
                                [pscustomobject]@{ id = 'list-x'; list = [pscustomobject]@{ template = 'genericList' }; parentReference = [pscustomobject]@{ siteId = 'contoso.sharepoint.com,site-1,web-1' } }
                            ) } }
                )
            }
        }

        It 'resolves each site to its own document library id' {
            Set-CIPPDBCacheSharePointSiteUsage -TenantFilter 'contoso.com'

            $Listing = ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteListing').Rows
            ($Listing | Where-Object id -EQ 's1').AutoMapUrl | Should -BeLike '*listId={list-1}'
            ($Listing | Where-Object id -EQ 's2').AutoMapUrl | Should -BeLike '*listId={list-2}'
        }

        It 'ignores non-document-library lists when resolving' {
            Set-CIPPDBCacheSharePointSiteUsage -TenantFilter 'contoso.com'

            $Listing = ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteListing').Rows
            ($Listing | Where-Object id -EQ 's1').AutoMapUrl | Should -Not -BeLike '*list-x*'
        }

        It 'writes both the listing and the usage rows' {
            Set-CIPPDBCacheSharePointSiteUsage -TenantFilter 'contoso.com'

            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteListing').Rows.Count | Should -Be 2
            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteUsage').Rows.Count | Should -Be 2
            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteUsage').Rows[0].siteId | Should -Be 'site-1'
            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteUsage').Rows[0].storageUsedInBytes | Should -Be 1073741824
            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteUsage').Rows[0].storageAllocatedInBytes | Should -Be (1024 * 1MB)
            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteUsage').Rows[0].ownerPrincipalName | Should -Be 'owner1@contoso.com'
            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteUsage').Rows[0].rootWebTemplate | Should -Be 'STS'
            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteUsage').Rows[1].rootWebTemplate | Should -Be 'Group'
            ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteUsage').Rows[0].reportRefreshDate | Should -Not -BeNullOrEmpty
        }

        It 'merges file-level archive fields from Get-CIPPSPOSite into the site listing' {
            Mock -CommandName Get-CIPPSPOSite -MockWith {
                @(
                    [pscustomobject]@{
                        Url                    = 'https://c/s1'
                        ArchivedFileDiskUsed   = 1073741824
                        AllowFileArchive       = $true
                    }
                    [pscustomobject]@{
                        Url                    = 'https://c/s2/'
                        ArchivedFileDiskUsed   = 0
                        AllowFileArchive       = $false
                    }
                )
            }

            Set-CIPPDBCacheSharePointSiteUsage -TenantFilter 'contoso.com'

            $Listing = ($script:DbWrites | Where-Object Type -EQ 'SharePointSiteListing').Rows
            ($Listing | Where-Object id -EQ 's1').archivedFileDiskUsedBytes | Should -Be 1073741824
            ($Listing | Where-Object id -EQ 's1').allowFileArchive | Should -BeTrue
            ($Listing | Where-Object id -EQ 's2').archivedFileDiskUsedBytes | Should -Be 0
            ($Listing | Where-Object id -EQ 's2').allowFileArchive | Should -BeFalse
        }
    }

    Context 'Set-CIPPDBCacheSiteActivity' {
        It 'writes nothing at all when every row is incomplete, preserving the previous cache' {
            # A OneDrive row with no ownerPrincipalName is not cache-complete, so it is skipped.
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-BulkReportResponse -OneDriveRows @(
                    [pscustomobject]@{ siteId = 'site-1'; siteUrl = 'https://c/p1'; displayName = 'P1'; ownerPrincipalName = $null; isDeleted = $false }
                )
            }
            Mock -CommandName New-GraphGetRequest -MockWith { @() }

            Set-CIPPDBCacheSiteActivity -TenantFilter 'contoso.com'

            # The critical guarantee: no Add-CIPPDbItem invocation, so no count row is overwritten.
            $script:DbWrites.Count | Should -Be 0
        }

        It 'writes an empty cache when there were no rows and nothing was skipped' {
            Mock -CommandName New-GraphBulkRequest -MockWith { New-BulkReportResponse }
            Mock -CommandName New-GraphGetRequest -MockWith { @() }

            Set-CIPPDBCacheSiteActivity -TenantFilter 'contoso.com'

            $script:DbWrites.Count | Should -Be 1
            $script:DbWrites[0].Type | Should -Be 'SiteActivity'
            $script:DbWrites[0].Rows.Count | Should -Be 0
            $script:DbWrites[0].AddCount | Should -BeTrue
        }

        It 'streams complete rows through a single writer invocation' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                New-BulkReportResponse -OneDriveRows @(
                    [pscustomobject]@{ siteId = 'od-1'; siteUrl = 'https://c/p1'; displayName = 'P1'; ownerPrincipalName = 'a@contoso.com'; ownerDisplayName = 'A'; isDeleted = $false; lastActivityDate = '2026-07-01' }
                ) -SharePointRows @(
                    [pscustomobject]@{ siteId = 'sp-1'; siteUrl = 'https://c/s1'; displayName = 'S1'; ownerDisplayName = 'B'; isDeleted = $false; lastActivityDate = '2026-07-02'; rootWebTemplate = 'STS' }
                )
            }
            Mock -CommandName New-GraphGetRequest -MockWith { @() }

            Set-CIPPDBCacheSiteActivity -TenantFilter 'contoso.com'

            # One invocation total: the steppable pipeline must not be reopened between the two loops,
            # otherwise orphan cleanup and the count row would run twice.
            $script:DbWrites.Count | Should -Be 1
            $script:DbWrites[0].Rows.Count | Should -Be 2
            $script:DbWrites[0].Rows.siteType | Should -Be @('OneDrive', 'SharePoint')
        }

        It 'keeps the teams properties in order on a Team-linked site' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                if ($Requests[0].id -eq 'sharePointUsage') {
                    return New-BulkReportResponse -SharePointRows @(
                        [pscustomobject]@{ siteId = 'sp-1'; siteUrl = 'https://c/s1'; displayName = 'S1'; ownerDisplayName = 'B'; isDeleted = $false; lastActivityDate = '2026-07-02'; rootWebTemplate = 'STS' }
                    ) -TeamRows @(
                        [pscustomobject]@{ teamId = 'grp-1'; teamName = 'Team One'; lastActivityDate = '2026-07-05' }
                    )
                }
                # Team site resolution: group -> site
                return @([pscustomobject]@{ id = 'grp-1'; status = 200; body = [pscustomobject]@{ sharepointIds = [pscustomobject]@{ siteId = 'sp-1' } } })
            }
            Mock -CommandName New-GraphGetRequest -MockWith { @([pscustomobject]@{ id = 'grp-1'; displayName = 'Group One' }) }

            Set-CIPPDBCacheSiteActivity -TenantFilter 'contoso.com'

            $Row = $script:DbWrites[0].Rows[0]
            $Row.siteType | Should -Be 'SharePointAndTeams'
            @($Row.PSObject.Properties.Name) | Select-Object -Last 4 |
                Should -Be @('teamsTeamId', 'teamsTeamName', 'teamsLastActivityDate', 'teamsLinkStatus')
            $Row.teamsTeamName | Should -Be 'Team One'
            $Row.effectiveLastActivityDate | Should -Be '2026-07-05'
        }
    }

    Context 'Set-CIPPDBCacheMailboxes' {
        BeforeEach {
            # 5 mailboxes; m1 grants send-on-behalf to m5's directory id.
            $Mailboxes = 1..5 | ForEach-Object {
                [pscustomobject]@{
                    id                        = "id-$_"
                    ExternalDirectoryObjectId = "id-$_"
                    UserPrincipalName         = "u$_@contoso.com"
                    DisplayName               = "User $_"
                    PrimarySMTPAddress        = "u$_@contoso.com"
                    ArchiveGuid               = '00000000-0000-0000-0000-000000000000'
                    EmailAddresses            = @()
                    GrantSendOnBehalfTo       = if ($_ -eq 1) { @('id-5') } else { @() }
                }
            }
            Mock -CommandName New-ExoBulkRequest -MockWith {
                @{ 'Get-Mailbox' = $Mailboxes; 'Get-User' = @() }
            }
            Mock -CommandName New-GraphGetRequest -MockWith { @() }
        }

        It 'sends each permission batch only its own mailboxes plus the delegate directory' {
            $Captured = $null
            Mock -CommandName Start-CIPPOrchestrator -MockWith {
                if ($InputObject.OrchestratorName -like 'MailboxPermissions*') { $script:Captured = $InputObject }
            }

            # Batch size for permissions is 50, so force several batches by checking the shape directly
            # with a small tenant: one batch, and its MailboxData must not exceed batch + delegates.
            Set-CIPPDBCacheMailboxes -TenantFilter 'contoso.com' -Types @('Permissions')

            $script:Captured | Should -Not -BeNullOrEmpty
            $Batch = @($script:Captured.Batch)[0]
            # 5 mailboxes in the batch; m5 is already in the batch so it is not appended again.
            @($Batch.MailboxData).Count | Should -Be 5
            @($Batch.MailboxData).UPN | Should -Be @('u1@contoso.com', 'u2@contoso.com', 'u3@contoso.com', 'u4@contoso.com', 'u5@contoso.com')
            # The batch's own mailboxes keep GrantSendOnBehalfTo so send-on-behalf rows still resolve.
            (@($Batch.MailboxData) | Where-Object UPN -EQ 'u1@contoso.com').GrantSendOnBehalfTo | Should -Be @('id-5')
        }

        It 'carries the delegate directory into batches that do not contain the delegate' {
            $script:Captured = $null
            Mock -CommandName Start-CIPPOrchestrator -MockWith {
                if ($InputObject.OrchestratorName -like 'MailboxPermissions*') { $script:Captured = $InputObject }
            }
            # 120 mailboxes -> 3 permission batches of 50/50/20. The delegate (id-120) sits in batch 3,
            # so batches 1 and 2 must still carry it for the id -> UPN lookup to resolve.
            $Many = 1..120 | ForEach-Object {
                [pscustomobject]@{
                    id                        = "id-$_"
                    ExternalDirectoryObjectId = "id-$_"
                    UserPrincipalName         = "u$_@contoso.com"
                    DisplayName               = "User $_"
                    PrimarySMTPAddress        = "u$_@contoso.com"
                    ArchiveGuid               = '00000000-0000-0000-0000-000000000000'
                    EmailAddresses            = @()
                    GrantSendOnBehalfTo       = if ($_ -eq 1) { @('id-120') } else { @() }
                }
            }
            Mock -CommandName New-ExoBulkRequest -MockWith { @{ 'Get-Mailbox' = $Many; 'Get-User' = @() } }

            Set-CIPPDBCacheMailboxes -TenantFilter 'contoso.com' -Types @('Permissions')

            $Batches = @($script:Captured.Batch)
            $Batches.Count | Should -Be 3
            # Batch 1: its own 50 + the single delegate entry appended = 51. Crucially not 120.
            @($Batches[0].MailboxData).Count | Should -Be 51
            @($Batches[0].MailboxData)[-1].UPN | Should -Be 'u120@contoso.com'
            # The appended delegate entry carries no GrantSendOnBehalfTo, so it emits no rows itself.
            @($Batches[0].MailboxData)[-1].GrantSendOnBehalfTo | Should -BeNullOrEmpty
            # Batch 3 already contains the delegate, so nothing is appended.
            @($Batches[2].MailboxData).Count | Should -Be 20
        }

        It 'still writes every mailbox row' {
            Set-CIPPDBCacheMailboxes -TenantFilter 'contoso.com' -Types @('None')

            $Write = $script:DbWrites | Where-Object Type -EQ 'Mailboxes'
            $Write.Rows.Count | Should -Be 5
            $Write.Rows[0].UPN | Should -Be 'u1@contoso.com'
        }

        It 'projects per-mailbox Auto Expanding Archive state when the org setting is off' {
            # The org lookup is a separate call from the mailbox bulk request; the default stub
            # returns nothing, which is the "org setting unavailable" path.
            $Mixed = @(
                [pscustomobject]@{ id = 'id-1'; ExternalDirectoryObjectId = 'id-1'; UserPrincipalName = 'u1@contoso.com'; DisplayName = 'User 1'; PrimarySMTPAddress = 'u1@contoso.com'; ArchiveGuid = '00000000-0000-0000-0000-000000000000'; EmailAddresses = @(); GrantSendOnBehalfTo = @(); AutoExpandingArchiveEnabled = $true }
                [pscustomobject]@{ id = 'id-2'; ExternalDirectoryObjectId = 'id-2'; UserPrincipalName = 'u2@contoso.com'; DisplayName = 'User 2'; PrimarySMTPAddress = 'u2@contoso.com'; ArchiveGuid = '00000000-0000-0000-0000-000000000000'; EmailAddresses = @(); GrantSendOnBehalfTo = @(); AutoExpandingArchiveEnabled = $false }
            )
            Mock -CommandName New-ExoBulkRequest -MockWith { @{ 'Get-Mailbox' = $Mixed; 'Get-User' = @() } }

            Set-CIPPDBCacheMailboxes -TenantFilter 'contoso.com' -Types @('None')

            $Rows = ($script:DbWrites | Where-Object Type -EQ 'Mailboxes').Rows
            $Rows[0].AutoExpandingArchive | Should -BeTrue
            $Rows[0].AutoExpandingArchiveScope | Should -Be 'Mailbox'
            $Rows[1].AutoExpandingArchive | Should -BeFalse
            $Rows[1].AutoExpandingArchiveScope | Should -Be 'None'
        }

        It 'lets the organization Auto Expanding Archive setting override every mailbox' {
            Mock -CommandName New-ExoRequest -MockWith { [pscustomobject]@{ AutoExpandingArchiveEnabled = $true } }

            Set-CIPPDBCacheMailboxes -TenantFilter 'contoso.com' -Types @('None')

            $Rows = ($script:DbWrites | Where-Object Type -EQ 'Mailboxes').Rows
            $Rows.Count | Should -Be 5
            @($Rows.AutoExpandingArchive) | Should -Not -Contain $false
            @($Rows.AutoExpandingArchiveScope) | Select-Object -Unique | Should -Be 'Organization'
        }

        It 'keeps caching mailboxes when the organization config lookup fails' {
            # Regression guard: the org lookup has its own try/catch precisely so a failure here
            # degrades to mailbox-level values instead of aborting the whole mailbox cache.
            Mock -CommandName New-ExoRequest -MockWith { throw 'org config unavailable' }

            Set-CIPPDBCacheMailboxes -TenantFilter 'contoso.com' -Types @('None')

            $Rows = ($script:DbWrites | Where-Object Type -EQ 'Mailboxes').Rows
            $Rows.Count | Should -Be 5
            $Rows[0].AutoExpandingArchiveScope | Should -Be 'None'
        }
    }

    Context 'Set-CIPPDBCacheUserRegistrationDetails' {
        It 'streams records into a single writer invocation' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @([pscustomobject]@{ id = 'u1' }, [pscustomobject]@{ id = 'u2' })
            }

            Set-CIPPDBCacheUserRegistrationDetails -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $script:DbWrites.Count | Should -Be 1
            $script:DbWrites[0].Rows.id | Should -Be @('u1', 'u2')
        }

        It 'does not run the writer end block when the report is empty' {
            # An empty report leaves the previous cache and its count row untouched. The writer is
            # opened before the Graph pipeline starts - its steppable pipeline has to capture this
            # collector's scope rather than New-GraphGetRequest's - so the invocation itself is
            # expected. What must not happen is End(), which writes the count row and clears orphans.
            Mock -CommandName New-GraphGetRequest -MockWith { @() }

            Set-CIPPDBCacheUserRegistrationDetails -TenantFilter 'contoso.com'

            $script:DbWrites.Count | Should -Be 1
            $script:DbWrites[0].Rows | Should -BeNullOrEmpty
            $script:DbWrites[0].EndRan | Should -BeFalse
        }
    }

    Context 'Set-CIPPDBCacheCopilotUsageUserDetail' {
        It 'streams records into the writer' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @([pscustomobject]@{ id = 'c1' }, [pscustomobject]@{ id = 'c2' })
            }

            Set-CIPPDBCacheCopilotUsageUserDetail -TenantFilter 'contoso.com'

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
            $script:DbWrites[0].Rows.id | Should -Be @('c1', 'c2')
        }

        It 'still writes the empty marker when there are no records' {
            # This collector always wrote a marker row, so unlike the report collectors above the
            # writer must still be invoked with zero rows.
            Mock -CommandName New-GraphGetRequest -MockWith { @() }

            Set-CIPPDBCacheCopilotUsageUserDetail -TenantFilter 'contoso.com'

            $script:DbWrites.Count | Should -Be 1
            $script:DbWrites[0].Rows.Count | Should -Be 0
            $script:DbWrites[0].AddCount | Should -BeTrue
        }
    }
}

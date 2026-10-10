# Pester tests for Get-CIPPSharePointSharingReport, the cache rollup behind ListSharePointSharing and
# the sharing PDF: link counts by classification, the sprawl signals, workload summaries and rankings.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharePointSharingReport.ps1')

    # Static stubs for the cache reads. No pass-through mocks.
    function New-CIPPDbRequest {
        param($TenantFilter, $Type, $Fields)
        switch ($Type) {
            'SharePointSharingLinks' {
                @(
                    [pscustomobject]@{ classification = 'Anonymous'; roles = @('write'); expirationDateTime = $null; itemType = 'Folder'; driveId = 'd1'; itemId = 'i1'; siteName = 'Sales'; driveName = 'Documents'; linkType = 'edit'; hasPassword = $false }
                    [pscustomobject]@{ classification = 'External'; roles = @('read'); expirationDateTime = '2026-12-31'; itemType = 'File'; driveId = 'd1'; itemId = 'i2'; siteName = 'Sales'; driveName = 'Documents'; linkType = 'view'; sharedWith = @('a@example.com', 'b@example.org', '') }
                    [pscustomobject]@{ classification = 'Internal'; roles = @('read'); itemType = 'File'; driveId = 'D1'; itemId = 'I1'; siteUrl = 'https://x/sites/Ops'; linkType = 'view'; hasPassword = $true }
                )
            }
            'SharePointSiteUsage' {
                @(
                    [pscustomobject]@{ rootWebTemplate = 'Group'; fileCount = '10'; storageUsedInBytes = 1GB }
                    [pscustomobject]@{ rootWebTemplate = 'Team Channel'; fileCount = 2; storageUsedInBytes = 1GB }
                    [pscustomobject]@{ rootWebTemplate = 'SitePage'; fileCount = 5; storageUsedInBytes = 2GB }
                )
            }
            'OneDriveUsage' { @([pscustomobject]@{ fileCount = 3; storageUsedInBytes = 512MB }) }
        }
    }
    function Get-CIPPDbItem {
        param($TenantFilter, $Type, [switch]$CountsOnly)
        if ($Type -eq 'OneDriveUsage') { return $null }
        [pscustomobject]@{ Timestamp = [datetime]'2026-09-01' }
    }
}

Describe 'Get-CIPPSharePointSharingReport' {
    BeforeAll { $script:Report = Get-CIPPSharePointSharingReport -TenantFilter 'contoso.onmicrosoft.com' }

    It 'counts links by classification and the sprawl signals' {
        $s = $script:Report.summary
        $s.totalLinks | Should -Be 3
        $s.anonymousLinks | Should -Be 1
        $s.externalLinks | Should -Be 1
        $s.internalLinks | Should -Be 1
        # d1|i1 and D1|I1 are the same item.
        $s.itemsShared | Should -Be 2
        $s.anonymousEditLinks | Should -Be 1
        $s.neverExpiringAnonymous | Should -Be 1
        $s.folderShares | Should -Be 1
        $s.passwordProtectedLinks | Should -Be 1
        $s.externalRecipients | Should -Be 2
    }

    It 'summarises each workload from the usage caches' {
        $s = $script:Report.summary
        # Group-connected and Teams channel sites both count as Teams.
        $s.teamsSites | Should -Be 2
        $s.teamsFiles | Should -Be 12
        $s.teamsStorageUsedGB | Should -Be 2
        $s.sharePointSites | Should -Be 1
        $s.sharePointFiles | Should -Be 5
        $s.sharePointStorageUsedGB | Should -Be 2
        $s.oneDriveAccounts | Should -Be 1
        $s.oneDriveFiles | Should -Be 3
        $s.oneDriveStorageUsedGB | Should -Be 0.5
        $s.linksSynced | Should -BeTrue
        $s.usageSynced | Should -BeTrue
        $s.lastDataRefresh | Should -Be ([datetime]'2026-09-01')
    }

    It 'ranks the busiest libraries, sites and recipients' {
        $r = $script:Report
        $r.topLibraries[0].library | Should -Be 'Sales / Documents'
        $r.topLibraries[0].links | Should -Be 2
        $r.topSites[0].site | Should -Be 'Sales'
        $r.topSites[0].links | Should -Be 2
        @($r.topRecipients).Count | Should -Be 2
        ($r.byScope | Where-Object { $_.scope -eq 'Anonymous' }).links | Should -Be 1
        ($r.byLinkType | Where-Object { $_.type -eq 'view' }).links | Should -Be 2
        @($r.links).Count | Should -Be 3
    }
}

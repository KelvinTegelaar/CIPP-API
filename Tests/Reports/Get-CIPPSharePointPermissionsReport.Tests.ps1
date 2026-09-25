# Pester tests for Get-CIPPSharePointPermissionsReport, the cache rollup behind ListSharePointPermissions
# and the permissions PDF: scan coverage, the oversharing signals and the derived display fields.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharePointPermissionsReport.ps1')

    # Static stubs for the cache reads. No pass-through mocks.
    function New-CIPPDbRequest {
        param($TenantFilter, $Type, $Fields)
        @(
            [pscustomobject]@{ rowType = 'Site'; siteName = 'Sales'; siteUrl = 'https://x/sites/Sales'; librariesScanned = 2; librariesWithUniquePermissions = 1; collectionStatus = 'Completed' }
            [pscustomobject]@{ rowType = 'Site'; siteName = 'Broken'; siteUrl = 'https://x/sites/Broken'; librariesScanned = 0; librariesWithUniquePermissions = 0; collectionStatus = 'Skipped'; collectionError = 'boom' }
            [pscustomobject]@{ rowType = 'Assignment'; principalId = 'p1'; permissionLevel = 'Full Control'; principalType = 'User'; scope = 'Site'; siteName = 'Sales'; siteUrl = 'https://x/sites/Sales' }
            [pscustomobject]@{ rowType = 'Assignment'; principalId = 'p2'; permissionLevel = 'Edit'; principalType = 'User'; isGuest = $true; scope = 'Library'; siteName = 'https://x/sites/Sales'; siteUrl = 'https://x/sites/Sales'; libraryTitle = 'Docs' }
            [pscustomobject]@{ rowType = 'Assignment'; principalId = 'p3'; permissionLevel = 'Read'; principalType = 'SharePoint Group'; broadClaim = 'Everyone'; scope = 'Site'; siteName = ''; siteUrl = 'https://x/sites/Sales' }
            # Limited Access and placeholder rows grant nothing and stay out of every signal.
            [pscustomobject]@{ rowType = 'Assignment'; principalId = 'p4'; permissionLevel = 'Full Control'; principalType = 'User'; isSystemManaged = $true; scope = 'Site' }
            [pscustomobject]@{ rowType = 'Assignment'; principalId = $null; scope = 'Library' }
        )
    }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) [pscustomobject]@{ Timestamp = [datetime]'2026-09-01' } }
}

Describe 'Get-CIPPSharePointPermissionsReport' {
    BeforeAll { $script:Report = Get-CIPPSharePointPermissionsReport -TenantFilter 'contoso.onmicrosoft.com' }

    It 'summarises scan coverage and the oversharing signals' {
        $s = $script:Report.summary
        $s.sitesScanned | Should -Be 2
        $s.sitesSkipped | Should -Be 1
        $s.librariesScanned | Should -Be 2
        $s.uniquePermissionLibraries | Should -Be 1
        $s.totalAssignments | Should -Be 3
        $s.broadClaimGrants | Should -Be 1
        $s.externalGrants | Should -Be 1
        $s.directFullControlGrants | Should -Be 1
        $s.permissionsSynced | Should -BeTrue
        $s.lastDataRefresh | Should -Be ([datetime]'2026-09-01')
    }

    It 'builds the chart datasets from the real assignments only' {
        $r = $script:Report
        ($r.byPermissionLevel | Where-Object { $_.level -eq 'Full Control' }).grants | Should -Be 1
        ($r.byPrincipalType | Where-Object { $_.type -eq 'User' }).grants | Should -Be 2
        $r.byBroadClaim[0].claim | Should -Be 'Everyone'
        $r.byBroadClaim[0].grants | Should -Be 1
        $r.topSitesByUniqueLibraries[0].site | Should -Be 'Sales'
        $r.topSitesByUniqueLibraries[0].libraries | Should -Be 1
        $r.skippedSites[0].error | Should -Be 'boom'
    }

    It 'derives the display fields on every assignment row' {
        $rows = @($script:Report.assignments)
        $rows.Count | Should -Be 5
        ($rows | Where-Object { $_.principalId -eq 'p2' }).appliesTo | Should -Be 'This library only'
        ($rows | Where-Object { $_.principalId -eq 'p1' }).appliesTo | Should -Be 'Whole site'
        # A URL or blank site name is replaced by a label taken from the URL.
        ($rows | Where-Object { $_.principalId -eq 'p2' }).siteName | Should -Be 'Sales'
        ($rows | Where-Object { $_.principalId -eq 'p3' }).siteName | Should -Be 'Sales'
    }
}

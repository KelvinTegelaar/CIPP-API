# Pester tests for Get-CIPPAlertHuntressRogueApps
# Covers the feed guard and describing matches from either rogue app list.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPAlertHuntressRogueApps.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $AlertPath) { throw 'Could not locate Get-CIPPAlertHuntressRogueApps.ps1 under Modules/' }

    # The real Config/MaliciousApps.json is read through $env:CIPPRootPath.
    $env:CIPPRootPath = $RepoRoot

    function Invoke-RestMethod { param($Uri, $ErrorAction) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-AlertMessage { param($tenant, $message) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception } }

    . $AlertPath

    # An appId that is in Config/MaliciousApps.json but deliberately not in the mocked feed.
    $script:CippApps = (Get-Content -Raw (Join-Path $RepoRoot 'Config/MaliciousApps.json') | ConvertFrom-Json).applications
    $script:CippOnly = $script:CippApps | Where-Object { $_.appId -eq '77468577-4f6e-40e7-b745-11d3d0c28095' } | Select-Object -First 1
    $script:Feed = @([pscustomobject]@{
            appId = 'feed-app-0001'; appDisplayName = 'Feed App'; description = 'From the feed'
            tags  = @('BEC'); references = @('https://example.test'); dateAdded = '2026-01-01'
        })

    function script:New-Principals {
        param([string[]]$AppIds)
        $Values = foreach ($Id in $AppIds) {
            [pscustomobject]@{ appId = $Id; appDisplayName = "SP $Id"; accountEnabled = $true; createdDateTime = '2026-01-01T00:00:00Z' }
        }
        @([pscustomobject]@{ body = [pscustomobject]@{ value = @($Values) } })
    }
}

Describe 'Get-CIPPAlertHuntressRogueApps' {
    BeforeEach {
        $script:Alerted = $null
        Mock -CommandName Write-AlertTrace -MockWith { param($cmdletName, $tenantFilter, $data) $script:Alerted = $data }
        Mock -CommandName Invoke-RestMethod -MockWith { $script:Feed }
        Mock -CommandName New-GraphBulkRequest -MockWith { script:New-Principals -AppIds @('feed-app-0001') }
    }

    Context 'feed availability' {
        It 'skips without alerting when the feed throws' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw 'GitHub Pages is down' }

            { Get-CIPPAlertHuntressRogueApps -TenantFilter 'contoso.onmicrosoft.com' } | Should -Not -Throw
            Should -Invoke -CommandName Write-AlertTrace -Times 0
        }

        It 'skips when the feed returns an error page rather than JSON' {
            # An HTML error page parses without throwing, so the shape has to be checked.
            Mock -CommandName Invoke-RestMethod -MockWith { '<!DOCTYPE html><html>404</html>' }

            Get-CIPPAlertHuntressRogueApps -TenantFilter 'contoso.onmicrosoft.com'
            Should -Invoke -CommandName Write-AlertTrace -Times 0
            Should -Invoke -CommandName New-GraphBulkRequest -Times 0
        }

        It 'skips when the feed is an empty array' {
            Mock -CommandName Invoke-RestMethod -MockWith { @() }

            Get-CIPPAlertHuntressRogueApps -TenantFilter 'contoso.onmicrosoft.com'
            Should -Invoke -CommandName Write-AlertTrace -Times 0
        }
    }

    Context 'describing a match' {
        It 'fills in an app that is only on the CIPP list' {
            Mock -CommandName New-GraphBulkRequest -MockWith { script:New-Principals -AppIds @($script:CippOnly.appId) }

            Get-CIPPAlertHuntressRogueApps -TenantFilter 'contoso.onmicrosoft.com'

            $Row = @($script:Alerted)[0]
            $Row.'App Name' | Should -BeExactly $script:CippOnly.name
            $Row.'App Id' | Should -BeExactly $script:CippOnly.appId
            $Row.'Description' | Should -Not -BeNullOrEmpty
            $Row.'Source' | Should -BeExactly 'CIPP'
        }

        It 'still fills in an app from the feed' {
            Get-CIPPAlertHuntressRogueApps -TenantFilter 'contoso.onmicrosoft.com'

            $Row = @($script:Alerted)[0]
            $Row.'App Name' | Should -BeExactly 'Feed App'
            $Row.'Source' | Should -BeExactly 'Huntress'
            $Row.'Listed On' | Should -BeExactly '2026-01-01'
        }

        It 'never emits a row without an app id' {
            Mock -CommandName New-GraphBulkRequest -MockWith {
                script:New-Principals -AppIds @($script:CippOnly.appId, 'feed-app-0001')
            }

            Get-CIPPAlertHuntressRogueApps -TenantFilter 'contoso.onmicrosoft.com'

            foreach ($Row in @($script:Alerted)) {
                $Row.'App Id' | Should -Not -BeNullOrEmpty
                $Row.'App Name' | Should -Not -BeNullOrEmpty
            }
        }
    }
}

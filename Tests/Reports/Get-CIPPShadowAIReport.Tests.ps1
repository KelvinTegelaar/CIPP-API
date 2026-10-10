# Pester tests for Get-CIPPShadowAIReport, the cache-plus-catalog rollup behind ListShadowAI and the
# Shadow AI PDF: Intune rows merge per tool, Entra apps pick up their grants, and both sources roll up
# into one tool list for the summary and charts.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPShadowAIReport.ps1')
    # The real catalog (Config/ShadowAI.json) resolves through CIPPRootPath.
    $env:CIPPRootPath = $RepoRoot

    # Static stubs for the cache, table and Graph reads. No pass-through mocks.
    function New-CIPPDbRequest {
        param($TenantFilter, $Type, $Fields)
        switch ($Type) {
            'DetectedApps' {
                @(
                    [pscustomobject]@{ displayName = 'GitHub Copilot'; publisher = 'GitHub, Inc.'; version = '1.0'; platform = 'Windows'; managedDevices = @(@{ id = 'dev1' }, @{ id = 'dev2' }) }
                    [pscustomobject]@{ displayName = 'GitHub Copilot'; publisher = 'CN=GitHub, Inc., O=GitHub'; version = '1.1'; platform = 'Windows'; managedDevices = @(@{ id = 'dev2' }, @{ id = 'dev3' }) }
                    [pscustomobject]@{ displayName = 'Notepad'; publisher = 'Microsoft'; version = '11'; platform = 'Windows'; managedDevices = @(@{ id = 'dev1' }) }
                )
            }
            'ServicePrincipals' { @([pscustomobject]@{ displayName = 'GitHub Copilot for Business'; appId = 'app-1'; id = 'sp-1'; createdDateTime = '2026-01-15T00:00:00Z' }) }
            'OAuth2PermissionGrants' { @([pscustomobject]@{ clientId = 'sp-1'; scope = 'User.Read Mail.Read User.Read' }) }
        }
    }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) [pscustomobject]@{ Timestamp = [datetime]'2026-09-01' } }
    function Get-CIPPTable { param($TableName) @{ Context = $TableName } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) @() }
    function New-GraphGetRequest { param($uri, $tenantid) throw 'no P1' }
    function Write-LogMessage { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
}

Describe 'Get-CIPPShadowAIReport' {
    BeforeAll { $script:Report = Get-CIPPShadowAIReport -TenantFilter 'contoso.onmicrosoft.com' }

    It 'merges the Intune inventory rows of one tool into a single row with distinct devices' {
        $apps = @($script:Report.detectedApps)
        $apps.Count | Should -Be 1
        $apps[0].aiTool | Should -Be 'GitHub Copilot'
        $apps[0].deviceCount | Should -Be 3
        $apps[0].version | Should -Be '1.0, 1.1'
        # The shortest publisher string wins over the certificate subject.
        $apps[0].publisher | Should -Be 'GitHub, Inc.'
        $apps[0].status | Should -Be 'Unsanctioned'
    }

    It 'matches Entra service principals and attaches their distinct granted scopes' {
        $apps = @($script:Report.consentedApps)
        $apps.Count | Should -Be 1
        $apps[0].applicationId | Should -Be 'app-1'
        @($apps[0].approvedPermissions) | Should -Be @('Mail.Read', 'User.Read')
        # The sign-in enrichment is best-effort: without P1 the counts stay at zero.
        $apps[0].activeUsersLast7Days | Should -Be 0
    }

    It 'rolls both sources up into one tool for the summary and charts' {
        $r = $script:Report
        $r.summary.aiToolsDetected | Should -Be 1
        $r.summary.deviceInstalls | Should -Be 3
        $r.summary.consentedAiApps | Should -Be 1
        $r.summary.intuneSynced | Should -BeTrue
        $r.topTools[0].tool | Should -Be 'GitHub Copilot'
        $r.topTools[0].devices | Should -Be 3
        $r.topTools[0].footprint | Should -Be 3
        $r.byRisk[0].risk | Should -Be 'Medium'
        $r.byRisk[0].tools | Should -Be 1
        $r.byCategory[0].category | Should -Be 'AI Coding'
    }
}

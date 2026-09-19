# CIPP.Core.Read is what every role needs in order to sign in, so an endpoint that declares it is
# reachable by every role that can log in at all. The Logbook and the Tools pages were moved onto
# their own permission objects so a least-privilege role can leave them out (issue #652). These
# tests keep them there.
BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:EntrypointRoot = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
    $RolePattern = [regex]::new('(?is)\.ROLE\s+([A-Za-z0-9.]+)')

    function Get-EntrypointRole {
        param([string]$Name)
        $File = Get-ChildItem -Path $script:EntrypointRoot -Filter "Invoke-$Name.ps1" -Recurse -File | Select-Object -First 1
        if (-not $File) { throw "Invoke-$Name.ps1 not found under $script:EntrypointRoot" }
        $Match = $RolePattern.Match([System.IO.File]::ReadAllText($File.FullName))
        if (-not $Match.Success) { throw "Invoke-$Name.ps1 declares no .ROLE" }
        return $Match.Groups[1].Value
    }
}

Describe 'Sign-in permission scope' {
    It 'keeps <Endpoint> on <Role>' -ForEach @(
        @{ Endpoint = 'ListLogs'; Role = 'CIPP.Logs.Read' }
        @{ Endpoint = 'ListIPWhitelist'; Role = 'CIPP.IPDatabase.Read' }
        @{ Endpoint = 'ListKnownIPDb'; Role = 'CIPP.IPDatabase.Read' }
        @{ Endpoint = 'ListBreachesAccount'; Role = 'CIPP.BreachLookup.Read' }
        @{ Endpoint = 'ListBreachesTenant'; Role = 'CIPP.BreachLookup.Read' }
        @{ Endpoint = 'ExecBreachSearch'; Role = 'CIPP.BreachLookup.Read' }
        @{ Endpoint = 'ListCommunityRepos'; Role = 'CIPP.TemplateLibrary.Read' }
        @{ Endpoint = 'ListCommunityRepoTemplates'; Role = 'CIPP.TemplateLibrary.Read' }
        @{ Endpoint = 'ExecCommunityRepo'; Role = 'CIPP.TemplateLibrary.ReadWrite' }
        @{ Endpoint = 'ListGeneratedReports'; Role = 'CIPP.ReportBuilder.Read' }
        @{ Endpoint = 'ListReportBuilderTemplates'; Role = 'CIPP.ReportBuilder.Read' }
        @{ Endpoint = 'ExecGenerateReportBuilderReport'; Role = 'CIPP.ReportBuilder.ReadWrite' }
        @{ Endpoint = 'ExecReportBuilderTemplate'; Role = 'CIPP.ReportBuilder.ReadWrite' }
    ) {
        Get-EntrypointRole -Name $Endpoint | Should -Be $Role
    }

    It 'declares no Tools endpoint on the sign-in permission' {
        $ToolsRoot = Join-Path $script:EntrypointRoot 'Tools'
        $OnCore = @(
            foreach ($File in Get-ChildItem -Path $ToolsRoot -Filter 'Invoke-*.ps1' -Recurse -File) {
                $Match = $RolePattern.Match([System.IO.File]::ReadAllText($File.FullName))
                if ($Match.Success -and $Match.Groups[1].Value -like 'CIPP.Core.*') { $File.Name }
            }
        )
        # ListGitHubReleaseNotes feeds the release notes dialog every signed-in user sees, and
        # ListBrandingPresets styles every PDF export, so both stay on the sign-in permission.
        $SharedByEveryPage = @('Invoke-ListGitHubReleaseNotes.ps1', 'Invoke-ListBrandingPresets.ps1')
        $OnCore | Where-Object { $_ -notin $SharedByEveryPage } | Should -BeNullOrEmpty
    }

    It 'still lets every role sign in through CIPP.Core.Read' {
        Get-EntrypointRole -Name 'ListTenants' | Should -Be 'CIPP.Core.Read'
        Get-EntrypointRole -Name 'GetVersion' | Should -Be 'CIPP.Core.Read'
    }
}

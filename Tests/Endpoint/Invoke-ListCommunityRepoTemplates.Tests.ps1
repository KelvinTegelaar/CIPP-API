# Pester tests for the Imported / Update available badges in Invoke-ListCommunityRepoTemplates.
# A template is matched to its repo file by SHA, then by name. A template renamed in CIPP loses the
# name match, so once the repo file changes it would look like it was never imported. The repo path
# stored at import time (SourcePath) survives a rename.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($TableName) @{ Context = $TableName } }
    function Get-CIPPAzDataTableEntity {
        param($Context, $Filter)
        switch ($Context) {
            'CommunityRepos' { [pscustomobject]@{ Name = 'repo'; FullName = 'Org/repo'; DefaultBranch = 'main'; TemplateTypes = '["IntuneTemplate"]' } }
            'templates' { $script:Rows }
        }
    }
    function Get-GitHubFileTree {
        param($FullName, $Branch)
        [pscustomobject]@{ tree = @(
                [pscustomobject]@{ path = 'IntuneTemplate/OIB_policy.json'; sha = 'new-sha'; size = 1 }
                [pscustomobject]@{ path = 'Config/NamedLocations/All Compliant Network locations.json'; sha = 'loc-sha'; size = 1 }
            ) }
    }
    function Invoke-GitHubApiRequest { param($Path) }
    function Get-CippBulkStatusCode { param($Total, $Failed) 200 }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tools/GitHub/Invoke-ListCommunityRepoTemplates.ps1')

    function Get-CatalogItem {
        $Response = Invoke-ListCommunityRepoTemplates -Request ([pscustomobject]@{ Query = @{} })
        @($Response.Body.Results)[0]
    }
    function New-Row($Name, $Sha, $SourcePath) {
        [pscustomobject]@{ PartitionKey = 'IntuneTemplate'; Source = 'Org/repo'; SHA = $Sha; SourcePath = $SourcePath; JSON = (@{ Displayname = $Name } | ConvertTo-Json -Compress) }
    }
}

Describe 'Invoke-ListCommunityRepoTemplates import badges' {
    It 'shows Imported for a template whose SHA matches the repo file' {
        $script:Rows = @(New-Row 'OIB policy' 'new-sha' 'IntuneTemplate/OIB_policy.json')
        $Item = Get-CatalogItem
        $Item.Imported | Should -BeTrue
        $Item.UpdateAvailable | Should -BeFalse
    }

    It 'shows Update available for a renamed template once the repo file changes' {
        $script:Rows = @(New-Row 'My renamed policy' 'old-sha' 'IntuneTemplate/OIB_policy.json')
        $Item = Get-CatalogItem
        $Item.Imported | Should -BeTrue
        $Item.UpdateAvailable | Should -BeTrue
    }

    It 'still matches by name when the row has no stored repo path' {
        $script:Rows = @(New-Row 'OIB policy' 'old-sha' $null)
        $Item = Get-CatalogItem
        $Item.Imported | Should -BeTrue
        $Item.UpdateAvailable | Should -BeTrue
    }

    It 'shows not imported when neither SHA, path nor name match' {
        $script:Rows = @(New-Row 'Something else' 'old-sha' 'IntuneTemplate/Other.json')
        (Get-CatalogItem).Imported | Should -BeFalse
    }

    It 'does not list named location files as templates' {
        $script:Rows = @()
        $Response = Invoke-ListCommunityRepoTemplates -Request ([pscustomobject]@{ Query = @{} })
        @($Response.Body.Results.Path) | Should -Be @('IntuneTemplate/OIB_policy.json')
    }
}

# Pester tests for Start-CIPPSharePointLibraryCopy: business-rule refusals throw ArgumentException

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Start-CIPPSharePointLibraryCopy.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    function New-GraphGetRequest { param($uri, $tenantid, $asapp) }
    function Test-CIPPSharePointLibraryCopyEligible { param($Template, $Title, $Name) }
    function Get-CIPPSharePointLibraryRootChildUris { param($TenantFilter, $SiteId, $SiteUrl, $ListId) }

    . $FunctionPath

    $script:Params = @{
        Mode         = 'PreflightLibraryCopy'
        TenantFilter = 'contoso.com'
        SourceSiteId = 'site-a'
        SourceListId = 'list-a'
        DestSiteId   = 'site-b'
        DestListId   = 'list-b'
    }
}

Describe 'Start-CIPPSharePointLibraryCopy' {
    BeforeEach {
        Mock New-GraphGetRequest {
            if ($uri -like '*/lists/*') { [pscustomobject]@{ id = ($uri -split '/lists/|\?')[1]; displayName = 'Docs'; name = 'Docs'; list = @{ template = 'documentLibrary' } } }
            else { [pscustomobject]@{ id = ($uri -split '/sites/|\?')[1]; webUrl = 'https://contoso.sharepoint.com/sites/x'; displayName = 'Site' } }
        }
        Mock Test-CIPPSharePointLibraryCopyEligible { [pscustomobject]@{ Eligible = $true } }
        Mock Get-CIPPSharePointLibraryRootChildUris { [pscustomobject]@{ EligibleRootCount = 3; ChildUris = @() } }
    }

    It 'returns the preflight estimate for an eligible copy' {
        (Start-CIPPSharePointLibraryCopy @script:Params).EligibleRootCount | Should -Be 3
    }

    It 'throws ArgumentException when <Case>' -ForEach @(
        @{ Case = 'a library is ineligible'; Setup = { Mock Test-CIPPSharePointLibraryCopyEligible { [pscustomobject]@{ Eligible = $false; Reason = 'Not a document library.' } } }; Overrides = @{}; Message = 'Not a document library.' }
        @{ Case = 'source and destination match'; Setup = {}; Overrides = @{ DestSiteId = 'site-a'; DestListId = 'list-a' }; Message = 'Source and destination library must be different.' }
        @{ Case = 'the source is empty'; Setup = { Mock Get-CIPPSharePointLibraryRootChildUris { [pscustomobject]@{ EligibleRootCount = 0 } } }; Overrides = @{}; Message = 'Source library has no eligible content to copy.' }
        @{ Case = 'the source has more than 1,000 items'; Setup = { Mock Get-CIPPSharePointLibraryRootChildUris { [pscustomobject]@{ EligibleRootCount = 1001 } } }; Overrides = @{}; Message = 'Source library has 1001 eligible root items*' }
    ) {
        . $Setup
        $CallParams = $script:Params.Clone()
        foreach ($Key in $Overrides.Keys) { $CallParams[$Key] = $Overrides[$Key] }

        { Start-CIPPSharePointLibraryCopy @CallParams } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage $Message
    }

    It 'lets upstream failures through untyped' {
        Mock New-GraphGetRequest { throw 'Graph 503' }

        $Thrown = { Start-CIPPSharePointLibraryCopy @script:Params } | Should -Throw -PassThru
        $Thrown.Exception | Should -Not -BeOfType ([System.ArgumentException])
    }
}

# Pester tests for Assert-CIPPSharePointHost and its use in the Graph request helpers

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Helpers = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper'

    function Get-AuthorisedRequest { param($Uri, $TenantID) $true }
    function Get-GraphToken { param($tenantid, $scope, $AsApp, $SkipCache, [switch]$UseCertificate) @{} }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CippUserAgent { param([switch]$SharePoint) 'CIPP/test' }
    function Get-NormalizedError { param($Message) $Message }
    function Invoke-CIPPRestMethod { }

    . (Join-Path $Helpers 'Assert-CIPPSharePointHost.ps1')
    . (Join-Path $Helpers 'New-GraphGetRequest.ps1')
    . (Join-Path $Helpers 'New-GraphPOSTRequest.ps1')
}

Describe 'Assert-CIPPSharePointHost' {
    It 'allows <Uri> with scope <Scope>' -ForEach @(
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://contoso.sharepoint.com/sites/HR/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://contoso-my.sharepoint.com/personal/u/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://CONTOSO-admin.sharepoint.com/_api/web' }
        @{ Scope = 'https://contoso-admin.sharepoint.com/.default'; Uri = 'https://contoso-admin.sharepoint.com/_api/SPO.Tenant' }
        @{ Scope = 'https://contoso-admin.sharepoint.com/.default'; Uri = 'https://contoso.sharepoint.com/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.us/.default'; Uri = 'https://contoso-my.sharepoint.us/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://contosoeur.sharepoint.com/sites/HR/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://fabrikam.sharepoint.com/_api/web' }
        @{ Scope = 'https://graph.microsoft.com/.default'; Uri = 'https://graph.microsoft.com/beta/sites/root' }
        @{ Scope = $null; Uri = 'https://graph.microsoft.com/beta/users' }
    ) {
        { Assert-CIPPSharePointHost -Uri $Uri -Scope $Scope } | Should -Not -Throw
    }

    It 'refuses <Uri> with scope <Scope>' -ForEach @(
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://evil.example.com/sites/HR/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://contoso.sharepoint.com.evil.example.com/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://contoso.sharepoint.com@evil.example.com/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://contoso.sharepoint.us/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'http://contoso.sharepoint.com/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'contoso.sharepoint.com/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://a.contoso.sharepoint.com/_api/web' }
        @{ Scope = 'https://contoso.sharepoint.com/.default'; Uri = 'https://evilsharepoint.com/_api/web' }
        @{ Scope = 'https://contoso-admin.sharepoint.com/.default'; Uri = 'https://evil.example.com/_api/web' }
    ) {
        { Assert-CIPPSharePointHost -Uri $Uri -Scope $Scope } | Should -Throw '*is not a SharePoint URL*'
    }
}

Describe 'Graph request helpers refuse a foreign host for a SharePoint token' {
    BeforeEach {
        Mock Get-GraphToken { @{} }
        Mock Invoke-CIPPRestMethod { }
    }

    It 'New-GraphGetRequest throws before requesting a token' {
        { New-GraphGetRequest -uri 'https://evil.example.com/_api/web' -tenantid 'contoso.onmicrosoft.com' -scope 'https://contoso.sharepoint.com/.default' -AsApp $true } | Should -Throw '*is not a SharePoint URL*'
        Should -Invoke Get-GraphToken -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'New-GraphPOSTRequest throws before requesting a token' {
        { New-GraphPOSTRequest -uri 'https://evil.example.com/_api/web' -tenantid 'contoso.onmicrosoft.com' -scope 'https://contoso.sharepoint.com/.default' -body '{}' -AsApp $true } | Should -Throw '*is not a SharePoint URL*'
        Should -Invoke Get-GraphToken -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'New-GraphPOSTRequest still sends to the tenant host' {
        New-GraphPOSTRequest -uri 'https://contoso.sharepoint.com/sites/HR/_api/web' -tenantid 'contoso.onmicrosoft.com' -scope 'https://contoso.sharepoint.com/.default' -body '{}' -AsApp $true
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
    }
}

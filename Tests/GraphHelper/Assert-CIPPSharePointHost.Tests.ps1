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
    . (Join-Path $Helpers 'Assert-CIPPMicrosoftHost.ps1')
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
        { New-GraphGetRequest -uri 'https://graph.microsoft.com/_api/web' -tenantid 'contoso.onmicrosoft.com' -scope 'https://contoso.sharepoint.com/.default' -AsApp $true } | Should -Throw '*is not a SharePoint URL*'
        Should -Invoke Get-GraphToken -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'New-GraphPOSTRequest throws before requesting a token' {
        { New-GraphPOSTRequest -uri 'https://graph.microsoft.com/_api/web' -tenantid 'contoso.onmicrosoft.com' -scope 'https://contoso.sharepoint.com/.default' -body '{}' -AsApp $true } | Should -Throw '*is not a SharePoint URL*'
        Should -Invoke Get-GraphToken -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'New-GraphPOSTRequest still sends to the tenant host' {
        New-GraphPOSTRequest -uri 'https://contoso.sharepoint.com/sites/HR/_api/web' -tenantid 'contoso.onmicrosoft.com' -scope 'https://contoso.sharepoint.com/.default' -body '{}' -AsApp $true
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
    }
}

Describe 'Assert-CIPPMicrosoftHost' {
    It 'allows <Uri>' -ForEach @(
        @{ Uri = 'https://graph.microsoft.com/beta/users' }
        @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers' }
        @{ Uri = 'https://outlook.office365.com/adminapi/beta/x/InvokeCommand' }
        @{ Uri = 'https://login.microsoftonline.com/x/oauth2/v2.0/token' }
        @{ Uri = 'https://contoso-admin.sharepoint.com/_api/web' }
        @{ Uri = 'https://admin.cloud.microsoft/api' }
        @{ Uri = 'https://management.azure.com/subscriptions' }
        @{ Uri = 'https://mde-rsp-apiportal-prd-weu.securitycenter.windows.com/api/cloud/portal/onboarding/intune/provision' }
        @{ Uri = 'https://intuneautopatchbeta-bwhtaqgefgcyaaa8.westeurope-01.azurewebsites.net/api/autoPatch' }
    ) {
        { Assert-CIPPMicrosoftHost -Uri $Uri } | Should -Not -Throw
    }

    It 'refuses <Uri>' -ForEach @(
        @{ Uri = 'https://evil.example.com/v1.0/users' }
        @{ Uri = 'https://graph.microsoft.com.evil.example/v1.0/users' }
        @{ Uri = 'https://evilmicrosoft.com/' }
        @{ Uri = 'https://victim.cloudapp.azure.com/' }
        @{ Uri = 'https://attacker.azurewebsites.net/' }
        @{ Uri = 'https://attacker.blob.core.windows.net/' }
        @{ Uri = 'http://graph.microsoft.com/v1.0/users' }
        @{ Uri = 'https://user:pw@graph.microsoft.com/v1.0/users' }
        @{ Uri = 'users' }
    ) {
        { Assert-CIPPMicrosoftHost -Uri $Uri } | Should -Throw
    }
}

Describe 'Graph request helpers refuse a non-Microsoft host' {
    BeforeEach {
        Mock Get-GraphToken { @{} }
        Mock Invoke-CIPPRestMethod { }
    }

    It 'New-GraphGetRequest throws before requesting a token' {
        { New-GraphGetRequest -uri 'https://evil.example.com/v1.0/users' -tenantid 'contoso.onmicrosoft.com' } | Should -Throw '*not a Microsoft service host*'
        Should -Invoke Get-GraphToken -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'New-GraphPOSTRequest throws before requesting a token' {
        { New-GraphPOSTRequest -uri 'https://evil.example.com/v1.0/users' -tenantid 'contoso.onmicrosoft.com' -body '{}' -AsApp $true } | Should -Throw '*not a Microsoft service host*'
        Should -Invoke Get-GraphToken -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }
}


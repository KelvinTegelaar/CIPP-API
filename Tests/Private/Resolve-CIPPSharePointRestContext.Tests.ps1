# Pester tests for Resolve-CIPPSharePointRestContext

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPSharePointRestContext.ps1'

    function Get-SharePointAdminLink { param($Public, $tenantFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Assert-CIPPSharePointHost.ps1')
    . $FunctionPath
}

Describe 'Resolve-CIPPSharePointRestContext' {
    BeforeEach {
        $script:SharePointInfo = [PSCustomObject]@{
            SharePointUrl = 'https://contoso.sharepoint.com'
            AdminUrl      = 'https://contoso-admin.sharepoint.com'
        }

        Mock -CommandName Get-SharePointAdminLink -MockWith { $script:SharePointInfo }
    }

    It 'builds scope, headers and site-scoped REST URIs from the admin link' {
        $Result = Resolve-CIPPSharePointRestContext -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl 'https://contoso.sharepoint.com/sites/HR/'

        $Result.Scope | Should -Be 'https://contoso.sharepoint.com/.default'
        $Result.Headers.Accept | Should -Be 'application/json;odata=nometadata'
        $Result.SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/HR'
        $Result.BaseUri | Should -Be 'https://contoso.sharepoint.com/sites/HR/_api'
        $Result.WebUri | Should -Be 'https://contoso.sharepoint.com/sites/HR/_api/web'
        $Result.SharePointInfo | Should -Be $script:SharePointInfo
    }

    It 'accepts the SharePoint host <_>' -ForEach @(
        'https://contoso-my.sharepoint.com/personal/user_contoso_com'
        'https://contoso-admin.sharepoint.com'
        'https://CONTOSO.sharepoint.com/sites/HR'
        'https://contosoeur.sharepoint.com/sites/HR'
    ) {
        (Resolve-CIPPSharePointRestContext -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl $_).BaseUri | Should -Be "$_/_api"
    }

    It 'refuses <_>' -ForEach @(
        'https://evil.example.com/sites/HR'
        'https://contoso.sharepoint.com.evil.example.com/sites/HR'
        'https://contoso.sharepoint.com@evil.example.com/sites/HR'
        'https://evil.example.com/contoso.sharepoint.com'
        'http://contoso.sharepoint.com/sites/HR'
        'contoso.sharepoint.com/sites/HR'
    ) {
        { Resolve-CIPPSharePointRestContext -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl $_ } | Should -Throw '*is not a SharePoint URL*'
    }

    It 'reuses SharePointInfo when supplied' {
        Resolve-CIPPSharePointRestContext -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl 'https://contoso.sharepoint.com/sites/HR' -SharePointInfo $script:SharePointInfo | Out-Null

        Should -Invoke Get-SharePointAdminLink -Times 0 -Exactly
    }

    It 'looks up SharePointInfo when it was not supplied' {
        Resolve-CIPPSharePointRestContext -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl 'https://contoso.sharepoint.com/sites/HR' | Out-Null

        Should -Invoke Get-SharePointAdminLink -Times 1 -Exactly -ParameterFilter {
            $Public -eq $false -and $tenantFilter -eq 'contoso.onmicrosoft.com'
        }
    }
}

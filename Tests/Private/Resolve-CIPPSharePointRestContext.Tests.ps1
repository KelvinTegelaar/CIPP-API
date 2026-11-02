# Pester tests for Resolve-CIPPSharePointRestContext

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPSharePointRestContext.ps1'

    function Get-SharePointAdminLink { param($Public, $tenantFilter) }

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

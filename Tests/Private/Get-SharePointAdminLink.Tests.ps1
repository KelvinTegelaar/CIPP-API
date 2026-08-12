# Pester tests for Get-SharePointAdminLink / Get-CIPPSharePointDomain
#
# SharePoint is only on sharepoint.com in the commercial cloud. Old German tenants are on
# sharepoint.de (issue #269), and every URL this function returns is used as both a request URI and
# an OAuth scope - a wrong domain means every SharePoint call for that tenant fails, and callers
# cache the result, so a bad value outlives the request that produced it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPSharePointDomain.ps1')

    # Minimal stub so Mock has a command to replace during tests
    function New-GraphGetRequest { param($uri, $asApp, $tenantid) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-SharePointAdminLink.ps1')
}

Describe 'Get-CIPPSharePointDomain' {
    It 'maps <TenantDomain> to <Expected>' -TestCases @(
        @{ TenantDomain = 'contoso.onmicrosoft.com'; Expected = 'sharepoint.com' }
        @{ TenantDomain = 'contoso.onmicrosoft.de'; Expected = 'sharepoint.de' }
        @{ TenantDomain = 'contoso.onmicrosoft.us'; Expected = 'sharepoint.us' }
        @{ TenantDomain = 'contoso.partner.onmschina.cn'; Expected = 'sharepoint.cn' }
    ) {
        param($TenantDomain, $Expected)
        Get-CIPPSharePointDomain -TenantDomain $TenantDomain | Should -Be $Expected
    }

    It 'falls back to the commercial domain for a vanity or empty domain' {
        Get-CIPPSharePointDomain -TenantDomain 'dev.contoso.com' | Should -Be 'sharepoint.com'
        Get-CIPPSharePointDomain -TenantDomain '' | Should -Be 'sharepoint.com'
    }
}

Describe 'Get-SharePointAdminLink' {
    Context 'resolving through Graph' {
        It 'takes the domain from the root site host rather than assuming .com' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [PSCustomObject]@{
                    id             = 'consoso.sharepoint.de,11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222'
                    webUrl         = 'https://consoso.sharepoint.de'
                    siteCollection = [PSCustomObject]@{ hostname = 'consoso.sharepoint.de' }
                }
            }

            $Result = Get-SharePointAdminLink -Public $false -TenantFilter 'consoso.onmicrosoft.de'

            $Result.TenantName | Should -Be 'consoso'
            $Result.SharePointDomain | Should -Be 'sharepoint.de'
            $Result.AdminUrl | Should -Be 'https://consoso-admin.sharepoint.de'
            $Result.SharePointUrl | Should -Be 'https://consoso.sharepoint.de'
        }

        It 'still resolves when siteCollection is absent and only the id carries the host' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [PSCustomObject]@{ id = 'consoso.sharepoint.de,11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222' }
            }

            (Get-SharePointAdminLink -Public $false -TenantFilter 'consoso.onmicrosoft.de').AdminUrl |
                Should -Be 'https://consoso-admin.sharepoint.de'
        }

        It 'still resolves when only webUrl is present' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [PSCustomObject]@{ webUrl = 'https://consoso.sharepoint.de/' }
            }

            (Get-SharePointAdminLink -Public $false -TenantFilter 'consoso.onmicrosoft.de').AdminUrl |
                Should -Be 'https://consoso-admin.sharepoint.de'
        }

        It 'keeps the commercial domain for a commercial tenant' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [PSCustomObject]@{ siteCollection = [PSCustomObject]@{ hostname = 'contoso.sharepoint.com' } }
            }

            (Get-SharePointAdminLink -Public $false -TenantFilter 'contoso.onmicrosoft.com').AdminUrl |
                Should -Be 'https://contoso-admin.sharepoint.com'
        }

        It 'keeps the DoD domain, which no domain-name mapping could derive' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [PSCustomObject]@{ siteCollection = [PSCustomObject]@{ hostname = 'contoso.sharepoint-mil.us' } }
            }

            (Get-SharePointAdminLink -Public $false -TenantFilter 'contoso.onmicrosoft.us').AdminUrl |
                Should -Be 'https://contoso-admin.sharepoint-mil.us'
        }

        It 'falls back to the commercial domain when the host is not a SharePoint one' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [PSCustomObject]@{ siteCollection = [PSCustomObject]@{ hostname = 'contoso.example.org' } }
            }

            (Get-SharePointAdminLink -Public $false -TenantFilter 'contoso.onmicrosoft.com').SharePointDomain |
                Should -Be 'sharepoint.com'
        }

        It 'throws instead of returning a link to nowhere when the root site has no host' {
            Mock -CommandName New-GraphGetRequest -MockWith { [PSCustomObject]@{} }

            { Get-SharePointAdminLink -Public $false -TenantFilter 'contoso.onmicrosoft.com' } |
                Should -Throw '*Could not determine the SharePoint tenant name*'
        }
    }

    Context 'resolving through autodiscover' {
        BeforeEach {
            # The SOAP response shape Invoke-RestMethod returns, down to the domain list.
            function New-AutodiscoverResponse {
                param([string[]]$Domains)
                [PSCustomObject]@{
                    Envelope = [PSCustomObject]@{
                        body = [PSCustomObject]@{
                            GetFederationInformationResponseMessage = [PSCustomObject]@{
                                response = [PSCustomObject]@{
                                    Domains = [PSCustomObject]@{ Domain = $Domains }
                                }
                            }
                        }
                    }
                }
            }
        }

        It 'resolves a single onmicrosoft.de domain to the .de SharePoint domain' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                New-AutodiscoverResponse -Domains @('meyerrechtsanwaelte.onmicrosoft.de', 'meyer.de')
            }

            $Result = Get-SharePointAdminLink -Public $true -TenantFilter 'meyerrechtsanwaelte.onmicrosoft.de'

            $Result.TenantName | Should -Be 'meyerrechtsanwaelte'
            $Result.AdminUrl | Should -Be 'https://meyerrechtsanwaelte-admin.sharepoint.de'
        }

        # A single match comes back from Where-Object as a bare string; indexing it with [0] yields
        # a [char], whose .Split() does not exist. Every single-domain tenant hit this.
        It 'handles a lone matching domain without indexing into the string' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                New-AutodiscoverResponse -Domains @('contoso.onmicrosoft.com')
            }

            { Get-SharePointAdminLink -Public $true -TenantFilter 'contoso.onmicrosoft.com' } | Should -Not -Throw
            (Get-SharePointAdminLink -Public $true -TenantFilter 'contoso.onmicrosoft.com').AdminUrl |
                Should -Be 'https://contoso-admin.sharepoint.com'
        }

        It 'throws when no onmicrosoft domain comes back' {
            Mock -CommandName Invoke-RestMethod -MockWith { New-AutodiscoverResponse -Domains @('contoso.com') }

            { Get-SharePointAdminLink -Public $true -TenantFilter 'contoso.com' } |
                Should -Throw '*Could not find onmicrosoft domain*'
        }
    }
}

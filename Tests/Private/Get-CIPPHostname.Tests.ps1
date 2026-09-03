# Pester tests for Get-CIPPHostname
# -PreferCustomDomain exists so links that outlive the request (GDAP onboarding URLs, webhook
# registrations) land on the custom domain even when an admin is browsing on the platform hostname.
# The trap is a deployment where the custom domain is NOT bound to the App Service - the classic
# Static Web App frontend with the API as a linked backend. There ARM truthfully reports only the
# *.azurewebsites.net hostname, which never serves the UI, so "authoritative" must not mean "use the
# platform hostname over the host the user is actually on". These tests pin that boundary.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPHostname.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPSiteHostname { param([switch]$AsRedirectUri, [switch]$IncludeStatus, [switch]$NoFallback) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . $FunctionPath
}

Describe 'Get-CIPPHostname' {
    BeforeEach {
        $script:DefaultHost = 'cippxyz.azurewebsites.net'
        $script:CustomHost = 'cipp.contoso.com'
        $script:OriginalWebsiteHostname = $env:WEBSITE_HOSTNAME
        $env:WEBSITE_HOSTNAME = $script:DefaultHost

        # A request that arrived through the custom domain, as it does behind a Static Web App
        $script:RequestHeaders = @{
            'x-ms-original-url' = "https://$script:CustomHost/api/ExecGDAPInvite"
            referer             = "https://$script:CustomHost/tenant/gdap-management/invites/add"
        }

        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'Config' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-CIPPSiteHostname -MockWith {
            [PSCustomObject]@{
                Hostnames         = @($script:DefaultHost, $script:CustomHost)
                DefaultHostname   = $script:DefaultHost
                CustomHostnames   = @($script:CustomHost)
                PreferredHostname = $script:CustomHost
                Discovered        = $true
                Error             = $null
            }
        }
    }

    AfterEach {
        $env:WEBSITE_HOSTNAME = $script:OriginalWebsiteHostname
    }

    Context 'When -PreferCustomDomain is set' {
        It 'uses the custom domain bound to the App Service ahead of the request host' {
            # Admin browsing on the platform hostname must not pin a stored link to it
            $Headers = @{ 'x-ms-original-url' = "https://$script:DefaultHost/api/ExecGDAPInvite" }

            $Result = Get-CIPPHostname -Headers $Headers -PreferCustomDomain

            $Result | Should -Be $script:CustomHost
        }

        It 'falls back to the request host when ARM answers but no custom domain is bound to the App Service' {
            # Static Web App deployments: the custom domain is on the SWA, the function app only has
            # its *.azurewebsites.net name, and that hostname never serves the frontend.
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{
                    Hostnames         = @($script:DefaultHost)
                    DefaultHostname   = $script:DefaultHost
                    CustomHostnames   = @()
                    PreferredHostname = $script:DefaultHost
                    Discovered        = $true
                    Error             = $null
                }
            }

            $Result = Get-CIPPHostname -Headers $script:RequestHeaders -PreferCustomDomain

            $Result | Should -Be $script:CustomHost
        }

        It 'falls back to the request host when the custom domain lookup is not authoritative' {
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{
                    Hostnames         = @()
                    DefaultHostname   = $script:DefaultHost
                    CustomHostnames   = @()
                    PreferredHostname = $null
                    Discovered        = $false
                    Error             = 'AuthorizationFailed'
                }
            }

            $Result = Get-CIPPHostname -Headers $script:RequestHeaders -PreferCustomDomain

            $Result | Should -Be $script:CustomHost
        }

        It 'still resolves the platform hostname when no custom domain is bound and there is no request' {
            # A unified container without a custom domain, called outside an HTTP request, must keep
            # resolving to the only hostname it has rather than coming back empty.
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{
                    Hostnames         = @($script:DefaultHost)
                    DefaultHostname   = $script:DefaultHost
                    CustomHostnames   = @()
                    PreferredHostname = $script:DefaultHost
                    Discovered        = $true
                    Error             = $null
                }
            }

            $Result = Get-CIPPHostname -PreferCustomDomain

            $Result | Should -Be $script:DefaultHost
        }
    }
}

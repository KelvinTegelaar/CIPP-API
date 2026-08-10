# Pester tests for Get-CIPPSiteHostname
# A container can carry several custom domains and each needs its own EasyAuth callback, so this
# function is the single source of truth for "which hostnames are bound". The important property
# is not just that the happy path enumerates them - it's that a FAILED lookup is distinguishable
# from a successful one, because callers use an empty "missing" set to tell customers everything
# can sign in. A silent fallback that looks like success is the bug these tests guard.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CIPPSiteHostname.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function New-CIPPAzRestRequest { param($Uri, $Method) }
    function Get-CIPPHostname { param($Headers, [switch]$Save) }

    . $FunctionPath
}

Describe 'Get-CIPPSiteHostname' {
    BeforeEach {
        $script:DefaultHost = 'cippxyz.azurewebsites.net'
        $script:CustomHostA = 'cipp.contoso.com'
        $script:CustomHostB = 'portal.fabrikam.com'
        $script:SubId = '11111111-1111-1111-1111-111111111111'

        $script:OriginalEnv = @{
            WEBSITE_SITE_NAME      = $env:WEBSITE_SITE_NAME
            WEBSITE_RESOURCE_GROUP = $env:WEBSITE_RESOURCE_GROUP
            WEBSITE_OWNER_NAME     = $env:WEBSITE_OWNER_NAME
            WEBSITE_HOSTNAME       = $env:WEBSITE_HOSTNAME
            IDENTITY_ENDPOINT      = $env:IDENTITY_ENDPOINT
            IDENTITY_HEADER        = $env:IDENTITY_HEADER
            AzureWebJobsStorage    = $env:AzureWebJobsStorage
            NonLocalHostAzurite    = $env:NonLocalHostAzurite
        }

        # Fully-configured App Service with a managed identity by default
        $env:WEBSITE_SITE_NAME = 'cippxyz'
        $env:WEBSITE_RESOURCE_GROUP = 'cipp-rg'
        $env:WEBSITE_OWNER_NAME = "$script:SubId+cipp-rg-CentralUSwebspace-Linux"
        $env:WEBSITE_HOSTNAME = $script:DefaultHost
        $env:IDENTITY_ENDPOINT = 'http://localhost:8081/msi/token'
        $env:IDENTITY_HEADER = 'stub-identity-header'
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=stub'
        $env:NonLocalHostAzurite = ''

        Mock -CommandName Get-CIPPHostname -MockWith { $script:CustomHostA }
        Mock -CommandName New-CIPPAzRestRequest -MockWith {
            [PSCustomObject]@{
                properties = [PSCustomObject]@{
                    hostNames       = @($script:DefaultHost, $script:CustomHostA, $script:CustomHostB)
                    defaultHostName = $script:DefaultHost
                }
            }
        }
    }

    AfterEach {
        foreach ($Key in $script:OriginalEnv.Keys) {
            Set-Item -Path "env:$Key" -Value $script:OriginalEnv[$Key]
        }
    }

    Context 'When ARM can be queried' {
        It 'returns every hostname bound to the site' {
            $Result = Get-CIPPSiteHostname

            $Result | Should -HaveCount 3
            $Result | Should -Contain $script:DefaultHost
            $Result | Should -Contain $script:CustomHostA
            $Result | Should -Contain $script:CustomHostB
        }

        It 'builds the ARM URI from the WEBSITE_* variables, splitting the subscription out of WEBSITE_OWNER_NAME' {
            Get-CIPPSiteHostname | Out-Null

            Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like "https://management.azure.com/subscriptions/$script:SubId/resourceGroups/cipp-rg/providers/Microsoft.Web/sites/cippxyz?api-version=*"
            }
        }

        It 'returns an EasyAuth callback for each hostname with -AsRedirectUri' {
            $Result = Get-CIPPSiteHostname -AsRedirectUri

            $Result | Should -HaveCount 3
            $Result | Should -Contain "https://$script:CustomHostA/.auth/login/aad/callback"
            $Result | Should -Contain "https://$script:CustomHostB/.auth/login/aad/callback"
        }

        It 'reports Discovered = true with no error under -IncludeStatus' {
            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.Discovered | Should -BeTrue
            $Result.Error | Should -BeNullOrEmpty
            $Result.Hostnames | Should -HaveCount 3
            $Result.RedirectUris | Should -HaveCount 3
        }

        It 'does not fall back to the stored instance URL' {
            Get-CIPPSiteHostname | Out-Null

            Should -Invoke Get-CIPPHostname -Times 0 -Exactly
        }
    }

    Context 'When picking the domain user-facing URLs should use' {
        It 'separates the custom domains from the hostname Azure handed out' {
            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.DefaultHostname | Should -Be $script:DefaultHost
            $Result.CustomHostnames | Should -HaveCount 2
            $Result.CustomHostnames | Should -Not -Contain $script:DefaultHost
        }

        It 'prefers the first custom domain when several are bound' {
            # Warmup runs on every node and they all have to land on the same answer, so the choice
            # has to be positional rather than "whichever one came back first this time".
            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.PreferredHostname | Should -Be $script:CustomHostA
        }

        It 'falls back to the platform hostname when no custom domain is bound' {
            Mock -CommandName New-CIPPAzRestRequest -MockWith {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        hostNames       = @($script:DefaultHost)
                        defaultHostName = $script:DefaultHost
                    }
                }
            }

            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.CustomHostnames | Should -HaveCount 0
            $Result.PreferredHostname | Should -Be $script:DefaultHost
        }

        It 'treats a regional *.azurewebsites.net hostname as the platform one even when ARM omits defaultHostName' {
            $script:RegionalHost = 'cippxyz-abc123.centralus-01.azurewebsites.net'
            Mock -CommandName New-CIPPAzRestRequest -MockWith {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        hostNames = @($script:RegionalHost, $script:CustomHostA)
                    }
                }
            }

            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.CustomHostnames | Should -Be @($script:CustomHostA)
            $Result.PreferredHostname | Should -Be $script:CustomHostA
        }
    }

    Context 'When -NoFallback is set' {
        # The fallback reads the stored instance URL, which is the very value the reconciler is
        # trying to verify. Feeding it back would make every stale value look self-consistent.
        BeforeEach {
            Mock -CommandName New-CIPPAzRestRequest -MockWith { throw 'AuthorizationFailed' }
        }

        It 'returns nothing instead of a best-effort list' {
            $Result = Get-CIPPSiteHostname -IncludeStatus -NoFallback

            $Result.Discovered | Should -BeFalse
            $Result.Hostnames | Should -HaveCount 0
            $Result.CustomHostnames | Should -HaveCount 0
            Should -Invoke Get-CIPPHostname -Times 0 -Exactly
        }

        It 'still surfaces why the lookup failed' {
            $Result = Get-CIPPSiteHostname -IncludeStatus -NoFallback

            $Result.Error | Should -Match 'AuthorizationFailed'
        }

        It 'does not suppress the fallback when ARM answered' {
            Mock -CommandName New-CIPPAzRestRequest -MockWith {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        hostNames       = @($script:DefaultHost, $script:CustomHostA)
                        defaultHostName = $script:DefaultHost
                    }
                }
            }

            $Result = Get-CIPPSiteHostname -IncludeStatus -NoFallback

            $Result.Discovered | Should -BeTrue
            $Result.PreferredHostname | Should -Be $script:CustomHostA
        }
    }

    Context 'When the domains cannot be queried' {
        It 'flags Discovered = false when ARM throws, and surfaces the reason' {
            Mock -CommandName New-CIPPAzRestRequest -MockWith { throw 'Azure REST API call failed: AuthorizationFailed' }

            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.Discovered | Should -BeFalse
            $Result.Error | Should -Match 'AuthorizationFailed'
        }

        It 'flags Discovered = false when ARM answers without any hostNames' {
            Mock -CommandName New-CIPPAzRestRequest -MockWith { [PSCustomObject]@{ properties = [PSCustomObject]@{} } }

            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.Discovered | Should -BeFalse
            $Result.Error | Should -Match 'no hostNames'
        }

        It 'does not call ARM at all when there is no managed identity' {
            $env:IDENTITY_ENDPOINT = ''
            $env:IDENTITY_HEADER = ''

            $Result = Get-CIPPSiteHostname -IncludeStatus

            Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly
            $Result.Discovered | Should -BeFalse
            $Result.Error | Should -Match 'managed identity'
        }

        It 'does not call ARM at all when not running in App Service' {
            $env:WEBSITE_SITE_NAME = ''

            $Result = Get-CIPPSiteHostname -IncludeStatus

            Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly
            $Result.Discovered | Should -BeFalse
            $Result.Error | Should -Match 'App Service'
        }

        It 'falls back to the platform hostname plus the last known instance URL' {
            Mock -CommandName New-CIPPAzRestRequest -MockWith { throw 'boom' }

            $Result = Get-CIPPSiteHostname

            # The custom domain from Config/InstanceProperties/CIPPURL is the whole point of the
            # fallback - without it a customer on a custom domain gets only the azurewebsites name.
            $Result | Should -HaveCount 2
            $Result | Should -Contain $script:DefaultHost
            $Result | Should -Contain $script:CustomHostA
        }

        It 'does not duplicate the hostname when the stored URL is the platform hostname' {
            Mock -CommandName New-CIPPAzRestRequest -MockWith { throw 'boom' }
            Mock -CommandName Get-CIPPHostname -MockWith { $script:DefaultHost }

            $Result = Get-CIPPSiteHostname

            $Result | Should -HaveCount 1
            $Result | Should -Be $script:DefaultHost
        }

        It 'still returns the platform hostname when the stored URL lookup itself fails' {
            Mock -CommandName New-CIPPAzRestRequest -MockWith { throw 'boom' }
            Mock -CommandName Get-CIPPHostname -MockWith { throw 'table storage unavailable' }

            { Get-CIPPSiteHostname } | Should -Not -Throw

            $Result = Get-CIPPSiteHostname
            $Result | Should -HaveCount 1
            $Result | Should -Be $script:DefaultHost
        }

        It 'drops a non-routable hostname rather than registering it' {
            Mock -CommandName New-CIPPAzRestRequest -MockWith { throw 'boom' }
            Mock -CommandName Get-CIPPHostname -MockWith { 'localhost' }

            $Result = Get-CIPPSiteHostname

            $Result | Should -Not -Contain 'localhost'
            $Result | Should -Be $script:DefaultHost
        }

        It 'returns an empty list rather than throwing when nothing at all is known' {
            $env:WEBSITE_SITE_NAME = ''
            $env:WEBSITE_HOSTNAME = ''
            Mock -CommandName Get-CIPPHostname -MockWith { $null }

            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.Discovered | Should -BeFalse
            $Result.Hostnames | Should -HaveCount 0
            $Result.RedirectUris | Should -HaveCount 0
        }
    }

    Context 'When running in local development' {
        # There is no App Service locally, so discovery always fails and we would fall through to
        # the stored CIPPURL - which Invoke-ExecPartnerWebhook -Save writes from the request host,
        # i.e. 'localhost'. The dev SSO AppId in DevSecrets is a REAL app registration, so that
        # would permanently graft a localhost callback onto it. Returning nothing is the point.
        BeforeEach {
            $env:WEBSITE_SITE_NAME = ''
            $env:WEBSITE_RESOURCE_GROUP = ''
            $env:WEBSITE_OWNER_NAME = ''
            $env:WEBSITE_HOSTNAME = ''
            $env:IDENTITY_ENDPOINT = ''
            $env:IDENTITY_HEADER = ''
            Mock -CommandName Get-CIPPHostname -MockWith { 'localhost' }
        }

        It 'returns nothing under Azurite so callers no-op' {
            $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'

            $Result = Get-CIPPSiteHostname -IncludeStatus

            $Result.Discovered | Should -BeFalse
            $Result.RedirectUris | Should -HaveCount 0
            Should -Invoke Get-CIPPHostname -Times 0 -Exactly
            Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly
        }

        It 'returns nothing under NonLocalHostAzurite so callers no-op' {
            $env:NonLocalHostAzurite = 'true'

            $Result = Get-CIPPSiteHostname -AsRedirectUri

            $Result | Should -HaveCount 0
            Should -Invoke Get-CIPPHostname -Times 0 -Exactly
        }
    }
}

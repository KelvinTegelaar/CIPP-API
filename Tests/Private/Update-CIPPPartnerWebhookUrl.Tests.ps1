# Pester tests for Update-CIPPPartnerWebhookUrl
# This is the one warmup step that writes to an external service, so most of what matters here is
# what it REFUSES to do. A wrong re-registration points Partner Center at an address CIPP is not
# served on, which stops tenant onboarding silently - nothing on the page fails, events just stop
# arriving. Every "does not write" test below guards a way that could happen.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Update-CIPPPartnerWebhookUrl.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CIPPSiteHostname { param([switch]$AsRedirectUri, [switch]$IncludeStatus, [switch]$NoFallback) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $scope) }
    function New-CIPPGraphSubscription { param($TenantFilter, $BaseURL, $EventType, $APIName, [switch]$PartnerCenter) }

    . $FunctionPath
}

Describe 'Update-CIPPPartnerWebhookUrl' {
    BeforeEach {
        $script:CustomHostA = 'cipp.contoso.com'
        $script:CustomHostB = 'portal.fabrikam.com'
        $script:TenantId = 'b0bdb332-24b4-4b86-b054-d86f4b461da3'
        $script:OriginalTenantId = $env:TenantID
        $env:TenantID = $script:TenantId

        $script:Enabled = $true
        $script:RegisteredUrl = "https://old.cipp.example/api/PublicWebhooks?CIPPID=$script:TenantId&Type=PartnerCenter"
        $script:RegisteredEvents = @('test-created', 'granular-admin-relationship-approved', 'subscription-updated')

        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'Config' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [PSCustomObject]@{ RowKey = 'PartnerWebhookOnboarding'; Enabled = $script:Enabled }
        }
        Mock -CommandName Get-CIPPSiteHostname -MockWith {
            [PSCustomObject]@{
                CustomHostnames   = @($script:CustomHostA)
                PreferredHostname = $script:CustomHostA
                Discovered        = $true
                Error             = $null
            }
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                webhookUrl    = $script:RegisteredUrl
                webhookEvents = $script:RegisteredEvents
            }
        }
        Mock -CommandName New-CIPPGraphSubscription -MockWith { 'Updated Partner Center Webhook subscription' }
    }

    AfterEach {
        $env:TenantID = $script:OriginalTenantId
    }

    Context 'When the subscription points at a stale URL' {
        It 're-registers against the bound custom domain' {
            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Updated | Should -BeTrue
            $Result.ExpectedUrl | Should -Be "https://$script:CustomHostA/api/PublicWebhooks?CIPPID=$script:TenantId&Type=PartnerCenter"
            Should -Invoke New-CIPPGraphSubscription -Times 1 -Exactly -ParameterFilter {
                $PartnerCenter -eq $true -and $BaseURL -eq $script:CustomHostA
            }
        }

        It 'carries the registered event types across' {
            # Without this the repair silently narrows the subscription to the two events
            # New-CIPPGraphSubscription always adds, dropping whatever the admin selected.
            Update-CIPPPartnerWebhookUrl | Out-Null

            Should -Invoke New-CIPPGraphSubscription -Times 1 -Exactly -ParameterFilter {
                $EventType -contains 'subscription-updated'
            }
        }

        It 'uses the first custom domain when several are bound' {
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{
                    CustomHostnames   = @($script:CustomHostA, $script:CustomHostB)
                    PreferredHostname = $script:CustomHostA
                    Discovered        = $true
                    Error             = $null
                }
            }

            Update-CIPPPartnerWebhookUrl | Out-Null

            Should -Invoke New-CIPPGraphSubscription -Times 1 -Exactly -ParameterFilter {
                $BaseURL -eq $script:CustomHostA
            }
        }

        It 'reports the failure rather than claiming success when the re-registration fails' {
            Mock -CommandName New-CIPPGraphSubscription -MockWith { 'Failed to create Partner Webhook Subscription: 403' }

            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Updated | Should -BeFalse
            $Result.Reason | Should -Match '403'
        }
    }

    Context 'When the subscription is already correct' {
        BeforeEach {
            $script:RegisteredUrl = "https://$script:CustomHostA/api/PublicWebhooks?CIPPID=$script:TenantId&Type=PartnerCenter"
        }

        It 'does not write' {
            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Updated | Should -BeFalse
            Should -Invoke New-CIPPGraphSubscription -Times 0 -Exactly
        }

        It 'ignores casing differences rather than re-registering every warmup' {
            $script:RegisteredUrl = $script:RegisteredUrl.ToUpper()

            Update-CIPPPartnerWebhookUrl | Out-Null

            Should -Invoke New-CIPPGraphSubscription -Times 0 -Exactly
        }
    }

    Context 'When it must not touch the subscription at all' {
        It 'does nothing when automated onboarding is disabled' {
            $script:Enabled = $false

            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Enabled | Should -BeFalse
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            Should -Invoke New-CIPPGraphSubscription -Times 0 -Exactly
        }

        It 'does nothing when the onboarding config has never been written' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }

            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Enabled | Should -BeFalse
            Should -Invoke New-CIPPGraphSubscription -Times 0 -Exactly
        }

        It 'does nothing when the bound hostname is not authoritative' {
            # The stored instance URL is not a safe substitute here: on a fresh container it is the
            # platform hostname, so "repairing" from it would break a working custom domain.
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{
                    CustomHostnames   = @()
                    PreferredHostname = $null
                    Discovered        = $false
                    Error             = 'Not running in App Service'
                }
            }

            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Updated | Should -BeFalse
            $Result.Reason | Should -Match 'App Service'
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            Should -Invoke New-CIPPGraphSubscription -Times 0 -Exactly
        }

        It 'does nothing when no partner tenant is configured' {
            $env:TenantID = ''

            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Updated | Should -BeFalse
            Should -Invoke New-CIPPGraphSubscription -Times 0 -Exactly
        }

        It 'does not write when the current subscription could not be read' {
            # A failed read is not a mismatch. Falling through here would create a subscription on
            # top of one we never managed to see.
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'Partner Center returned 403' }

            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Updated | Should -BeFalse
            $Result.Reason | Should -Match '403'
            Should -Invoke New-CIPPGraphSubscription -Times 0 -Exactly
        }
    }

    Context 'When there is no subscription in Partner Center at all' {
        It 'creates one, because onboarding is enabled and expects it to exist' {
            Mock -CommandName New-GraphGetRequest -MockWith { $null }
            Mock -CommandName New-CIPPGraphSubscription -MockWith { 'Created Partner Center Webhook subscription' }

            $Result = Update-CIPPPartnerWebhookUrl

            $Result.Updated | Should -BeTrue
            Should -Invoke New-CIPPGraphSubscription -Times 1 -Exactly
        }
    }

    Context 'When something unexpected breaks' {
        It 'never throws out of warmup' {
            Mock -CommandName Get-CIPPTable -MockWith { throw 'table storage unavailable' }

            { Update-CIPPPartnerWebhookUrl } | Should -Not -Throw

            $Result = Update-CIPPPartnerWebhookUrl
            $Result.Updated | Should -BeFalse
            $Result.Reason | Should -Match 'table storage unavailable'
        }
    }
}

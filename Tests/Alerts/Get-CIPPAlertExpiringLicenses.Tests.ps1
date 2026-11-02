# Pester tests for Get-CIPPAlertExpiringLicenses.
# Each emitted row must carry the Graph subscription id as `Id` so Get-AlertContentHash keys the
# snooze fingerprint on it rather than falling back to `Message`, which embeds DaysUntilRenew and
# therefore changes on every scheduled run (a snooze could never match the next run).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertExpiringLicenses.ps1'
    $HashPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AlertContentHash.ps1'

    function Get-CIPPLicenseOverview { param($TenantFilter, [switch]$AlertMode) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . $AlertPath
    . $HashPath
}

Describe 'Get-CIPPAlertExpiringLicenses' {
    BeforeEach {
        $script:CapturedAlertData = $null
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedAlertData = @($data)
        }
    }

    Context 'snooze identity' {
        It 'emits the subscription id as Id on every row' {
            Mock Get-CIPPLicenseOverview {
                [pscustomobject]@{
                    License = 'Microsoft 365 Business Premium'; skuId = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46'
                    CountUsed = 10; CountAvailable = 2; Tenant = 'contoso.onmicrosoft.com'
                    TermInfo = @(
                        [pscustomobject]@{ Status = 'Enabled'; Term = 'Yearly'; TotalLicenses = 12; DaysUntilRenew = 24; NextLifecycle = '2026-10-05T00:00:00Z'; SubscriptionId = '11111111-aaaa-4aaa-8aaa-111111111111' },
                        [pscustomobject]@{ Status = 'Enabled'; Term = 'Monthly'; TotalLicenses = 5; DaysUntilRenew = 44; NextLifecycle = '2026-11-01T00:00:00Z'; SubscriptionId = '33333333-cccc-4ccc-8ccc-333333333333' }
                    )
                }
            }

            Get-CIPPAlertExpiringLicenses -InputValue @{ ExpiringLicensesDays = 60; ExpiringLicensesUnassignedOnly = $true } -TenantFilter 'contoso.onmicrosoft.com'

            $script:CapturedAlertData.Count | Should -Be 2
            $script:CapturedAlertData.Id | Should -Be @('11111111-aaaa-4aaa-8aaa-111111111111', '33333333-cccc-4ccc-8ccc-333333333333')
        }

        It 'produces the same content hash on consecutive runs even though DaysUntilRenew changes' {
            $script:Days = 24
            Mock Get-CIPPLicenseOverview {
                [pscustomobject]@{
                    License = 'Microsoft 365 Business Premium'; skuId = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46'
                    CountUsed = 10; CountAvailable = 2; Tenant = 'contoso.onmicrosoft.com'
                    TermInfo = @([pscustomobject]@{ Status = 'Enabled'; Term = 'Yearly'; TotalLicenses = 12; DaysUntilRenew = $script:Days; NextLifecycle = '2026-10-05T00:00:00Z'; SubscriptionId = '11111111-aaaa-4aaa-8aaa-111111111111' })
                }
            }

            Get-CIPPAlertExpiringLicenses -InputValue @{ ExpiringLicensesDays = 60; ExpiringLicensesUnassignedOnly = $true } -TenantFilter 'contoso.onmicrosoft.com'
            $FirstHash = (Get-AlertContentHash -AlertItem $script:CapturedAlertData[0]).ContentHash

            $script:Days = 17   # one week later
            Get-CIPPAlertExpiringLicenses -InputValue @{ ExpiringLicensesDays = 60; ExpiringLicensesUnassignedOnly = $true } -TenantFilter 'contoso.onmicrosoft.com'
            $SecondHash = (Get-AlertContentHash -AlertItem $script:CapturedAlertData[0]).ContentHash

            $script:CapturedAlertData[0].Message | Should -Match 'expiring in 17 days'
            $SecondHash | Should -Be $FirstHash
        }
    }
}

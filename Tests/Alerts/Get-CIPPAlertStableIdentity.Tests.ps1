# Alert lifecycle matches items by Get-AlertContentHash (UserPrincipalName > Id > Message). Items that
# only carry a Message with live numbers re-notify every run, so each alert needs a stable Id.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Alerts = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts'

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $useSystemMailbox) }
    function New-GraphGetRequest { param($uri, $tenantid, $noPagination) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }
    function Get-CIPPLicenseOverview { param($TenantFilter, [switch]$AlertMode) }
    function Get-CIPPDomainAnalyser { param($TenantFilter) }
    function Get-CippException { param($Exception) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData, $tenantFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AlertContentHash.ps1')
    foreach ($Name in 'TERRL', 'EntraConnectSyncStatus', 'QuotaUsed', 'EntraLicenseUtilization', 'OverusedLicenses', 'UnusedLicenses', 'LowDomainScore', 'SecureScore') {
        . (Join-Path $Alerts "Get-CIPPAlert$Name.ps1")
    }

    function Get-RunHashes {
        param([scriptblock]$Run)
        $script:Captured = $null
        & $Run
        @($script:Captured | Where-Object { $null -ne $_ } | ForEach-Object { (Get-AlertContentHash -AlertItem $_).ContentHash })
    }
}

Describe 'Alert item identity is stable while live numbers change' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Get-CIPPTextReplacement { '' }
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:Captured = @($data)
        }
    }

    It 'TERRL hashes the same at 83.4% and 91.2%' {
        $script:Observed = 834
        Mock New-ExoRequest { [pscustomobject]@{ ObservedValue = $script:Observed; Threshold = 1000; EnforcementEnabled = $true; Verdict = 'Ok' } }
        $A = Get-RunHashes { Get-CIPPAlertTERRL -InputValue 80 -TenantFilter 'contoso.onmicrosoft.com' }
        $script:Observed = 912
        $B = Get-RunHashes { Get-CIPPAlertTERRL -InputValue 80 -TenantFilter 'contoso.onmicrosoft.com' }
        $A.Count | Should -Be 1
        $B | Should -Be $A
    }

    It 'Entra Connect sync hashes the same as the stale hours grow' {
        $script:Age = 100
        Mock New-GraphGetRequest {
            $Old = (Get-Date).AddHours(-$script:Age).ToUniversalTime()
            [pscustomobject]@{ onPremisesSyncEnabled = $true; onPremisesLastSyncDateTime = $Old; onPremisesLastPasswordSyncDateTime = (Get-Date).ToUniversalTime() }
        }
        $A = Get-RunHashes { Get-CIPPAlertEntraConnectSyncStatus -TenantFilter 'contoso.onmicrosoft.com' }
        $script:Age = 130
        $B = Get-RunHashes { Get-CIPPAlertEntraConnectSyncStatus -TenantFilter 'contoso.onmicrosoft.com' }
        $A.Count | Should -Be 1
        $B | Should -Be $A
    }

    It 'QuotaUsed hashes the same as mailbox usage moves' {
        $script:Used = 96636764160
        Mock New-GraphGetRequest {
            [pscustomobject]@{ userPrincipalName = 'user@contoso.com'; recipientType = 'UserMailbox'; storageUsedInBytes = $script:Used; prohibitSendReceiveQuotaInBytes = 107374182400; isDeleted = 'False' }
        }
        $A = Get-RunHashes { Get-CIPPAlertQuotaUsed -InputValue @{ QuotaUsedQuota = 90 } -TenantFilter 'contoso.onmicrosoft.com' }
        $script:Used = 103079215104
        $B = Get-RunHashes { Get-CIPPAlertQuotaUsed -InputValue @{ QuotaUsedQuota = 90 } -TenantFilter 'contoso.onmicrosoft.com' }
        $A.Count | Should -Be 1
        $B | Should -Be $A
    }

    It 'Entra license utilization hashes the same as counts change, and P1 differs from P2' {
        $script:Used = 120
        Mock New-GraphGetRequest {
            [pscustomobject]@{
                entitledP1LicenseCount = 100; entitledP2LicenseCount = 100
                p1FeatureUtilizations  = [pscustomobject]@{ conditionalAccess = [pscustomobject]@{ userCount = 300 + $script:Used } }
                p2FeatureUtilizations  = [pscustomobject]@{ riskBasedConditionalAccess = [pscustomobject]@{ userCount = $script:Used } }
            }
        }
        $A = Get-RunHashes { Get-CIPPAlertEntraLicenseUtilization -TenantFilter 'contoso.onmicrosoft.com' }
        $script:Used = 150
        $B = Get-RunHashes { Get-CIPPAlertEntraLicenseUtilization -TenantFilter 'contoso.onmicrosoft.com' }
        $A.Count | Should -Be 2
        $A[0] | Should -Not -Be $A[1]
        $B | Should -Be $A
    }

    It 'Overused and Unused licenses hash the same as counts change' {
        $script:Used = 12
        Mock Get-CIPPLicenseOverview {
            [pscustomobject]@{ License = 'Microsoft 365 E3'; skuId = 'sku-1'; skuPartNumber = 'E3'; CountUsed = $script:Used; TotalLicenses = 10; CountAvailable = (10 - $script:Used) }
        }
        $A = Get-RunHashes { Get-CIPPAlertOverusedLicenses -TenantFilter 'contoso.onmicrosoft.com' }
        $script:Used = 15
        $B = Get-RunHashes { Get-CIPPAlertOverusedLicenses -TenantFilter 'contoso.onmicrosoft.com' }
        $A.Count | Should -Be 1
        $B | Should -Be $A

        $script:Used = 4
        $C = Get-RunHashes { Get-CIPPAlertUnusedLicenses -TenantFilter 'contoso.onmicrosoft.com' }
        $script:Used = 2
        $D = Get-RunHashes { Get-CIPPAlertUnusedLicenses -TenantFilter 'contoso.onmicrosoft.com' }
        $C.Count | Should -Be 1
        $D | Should -Be $C
    }

    It 'LowDomainScore hashes the same as the score changes' {
        $script:Score = 40
        Mock Get-CIPPDomainAnalyser {
            [pscustomobject]@{ Domain = 'contoso.com'; ScorePercentage = $script:Score; ScoreExplanation = 'No DMARC' }
        }
        $A = Get-RunHashes { Get-CIPPAlertLowDomainScore -TenantFilter 'contoso.onmicrosoft.com' }
        $script:Score = 55
        $B = Get-RunHashes { Get-CIPPAlertLowDomainScore -TenantFilter 'contoso.onmicrosoft.com' }
        $A.Count | Should -Be 1
        $B | Should -Be $A
    }

    It 'SecureScore drop hashes the same as the drop size changes' {
        $script:Current = 60
        Mock New-GraphGetRequest {
            @([pscustomobject]@{ currentScore = $script:Current; maxScore = 100 }, [pscustomobject]@{ currentScore = 80; maxScore = 100 })
        }
        $In = @{ ThresholdType = @{ value = 'drop' }; InputValue = 10 }
        $A = Get-RunHashes { Get-CIPPAlertSecureScore -InputValue $In -TenantFilter 'contoso.onmicrosoft.com' }
        $script:Current = 50
        $B = Get-RunHashes { Get-CIPPAlertSecureScore -InputValue $In -TenantFilter 'contoso.onmicrosoft.com' }
        $A.Count | Should -Be 1
        $B | Should -Be $A
    }
}

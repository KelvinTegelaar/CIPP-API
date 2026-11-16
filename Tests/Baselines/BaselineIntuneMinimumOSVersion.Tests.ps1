# IntuneMinimumOSVersion: which version a platform should require, and which policies are behind it.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPOSLifecycle { param($Product) }
    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/ConvertTo-CIPPBaselineOSVersion.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineMinimumOSTarget.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks/Get-CIPPBaselineIntuneMinimumOSVersionState.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Now = [datetime]'2026-11-16'

    function script:New-Release {
        param([string]$Name, [string]$Released, [string]$Latest, [string]$LatestDate, [bool]$Maintained = $true, [string]$Eol, [bool]$Lts = $false)
        [pscustomobject]@{ name = $Name; releaseDate = $Released; isLts = $Lts; isMaintained = $Maintained; eolFrom = $Eol; latestVersion = $Latest; latestDate = $LatestDate }
    }

    function script:New-Policy {
        param([string]$Name, [string]$Type, [hashtable]$Settings = @{})
        $Policy = [ordered]@{ id = "id-$Name"; displayName = $Name; '@odata.type' = "#microsoft.graph.$Type" }
        foreach ($Key in $Settings.Keys) { $Policy[$Key] = $Settings[$Key] }
        [pscustomobject]$Policy
    }

    function script:New-OSItem {
        param([hashtable]$Variables = @{})
        [pscustomobject]@{ Variables = [pscustomobject]$Variables }
    }
}

Describe 'Get-CIPPBaselineMinimumOSTarget' {
    BeforeAll {
        $script:Apple = @(
            (New-Release '27' '2026-09-14' '27.2.1' '2026-11-09'),
            (New-Release '26' '2025-09-15' '26.7.3' '2026-11-09'),
            (New-Release '18' '2024-09-16' '18.7.12' '2026-10-20'),
            (New-Release '17' '2023-09-18' '17.7.7' '2025-05-13' $false '2025-05-13')
        )
        $script:Windows = @(
            (New-Release '11-25h2-e' '2025-09-30' '10.0.26200'),
            (New-Release '11-25h2-w' '2025-09-30' '10.0.26200'),
            (New-Release '11-24h2-e' '2024-10-01' '10.0.26100'),
            (New-Release '11-24h2-w' '2024-10-01' '10.0.26100' '' $false '2026-10-13'),
            # Past end of life but still flagged maintained because of paid extended support.
            (New-Release '10-22h2' '2022-10-18' '10.0.19045' '' $true '2025-10-14'),
            (New-Release '10-1809-e-lts' '2018-11-13' '10.0.17763' '' $true '' $true)
        )
        $script:Android = @(
            (New-Release '17' '2026-06-16'),
            (New-Release '14' '2023-10-04'),
            (New-Release '13' '2022-08-15' '' '' $false '2026-03-02')
        )
    }

    It 'requires the latest update of the oldest supported release once it is past the grace period' {
        (Get-CIPPBaselineMinimumOSTarget -Platform iOS -Releases $script:Apple -Now $script:Now).Version | Should -Be '18.7.12'
    }

    It 'requires only the release itself while its latest update is inside the grace period' {
        (Get-CIPPBaselineMinimumOSTarget -Platform iOS -Releases $script:Apple -Scope latest -Now $script:Now).Version | Should -Be '27.0'
        (Get-CIPPBaselineMinimumOSTarget -Platform iOS -Releases $script:Apple -Scope latest -CadenceDays 0 -Now $script:Now).Version | Should -Be '27.2.1'
    }

    It 'limits the allowed releases to the latest two' {
        (Get-CIPPBaselineMinimumOSTarget -Platform iOS -Releases $script:Apple -Scope latestTwo -CadenceDays 0 -Now $script:Now).Version | Should -Be '26.7.3'
    }

    It 'keeps a release allowed for the grace period after its end of life' {
        $Releases = @((New-Release '15' '2024-09-16' '15.8.3' '2026-10-01'), (New-Release '14' '2023-09-26' '14.8.9' '2026-08-06' $false '2026-11-10'))
        (Get-CIPPBaselineMinimumOSTarget -Platform macOS -Releases $Releases -Now $script:Now).Version | Should -Be '14.8.9'
        (Get-CIPPBaselineMinimumOSTarget -Platform macOS -Releases $Releases -CadenceDays 0 -Now $script:Now).Version | Should -Be '15.8.3'
    }

    It 'uses the oldest supported Android release and the monthly patch level after the grace period' {
        $Target = Get-CIPPBaselineMinimumOSTarget -Platform Android -Releases $script:Android -Now $script:Now
        $Target.Version | Should -Be '14'
        $Target.PatchLevel | Should -Be '2026-11-01'
        (Get-CIPPBaselineMinimumOSTarget -Platform Android -Releases $script:Android -CadenceDays 20 -Now $script:Now).PatchLevel | Should -Be '2026-10-01'
    }

    It 'uses the lowest supported Windows build and ignores LTSC and extended support releases' {
        (Get-CIPPBaselineMinimumOSTarget -Platform Windows -Releases $script:Windows -Now $script:Now).Version | Should -Be '10.0.26100.0'
        (Get-CIPPBaselineMinimumOSTarget -Platform Windows -Releases $script:Windows -Scope latest -Now $script:Now).Version | Should -Be '10.0.26200.0'
    }

    It 'returns nothing when no release is supported' {
        Get-CIPPBaselineMinimumOSTarget -Platform iOS -Releases @($script:Apple[3]) -Now $script:Now | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineIntuneMinimumOSVersionState' {
    BeforeEach {
        $script:Compliance = @()
        $script:AppProtection = @()
        Mock Get-CIPPOSLifecycle { @([pscustomobject]@{ name = 'x' }) }
        Mock Get-CIPPBaselineCacheRows { if ($Type -eq 'IntuneDeviceCompliancePolicies') { $script:Compliance } else { $script:AppProtection } }
        # Required values come back for the configured grace period, warning values for none.
        Mock Get-CIPPBaselineMinimumOSTarget {
            $IsWarning = $CadenceDays -eq 0
            switch ($Platform) {
                'Android' { [pscustomobject]@{ Version = '14'; PatchLevel = $(if ($IsWarning) { '2026-11-01' } else { '2026-10-01' }) } }
                'Windows' { [pscustomobject]@{ Version = '10.0.26100.0'; PatchLevel = $null } }
                default { [pscustomobject]@{ Version = $(if ($IsWarning) { '18.7.12' } else { '18.7.11' }); PatchLevel = $null } }
            }
        }
    }

    It 'flags a policy that is behind or has no minimum, and never lowers a higher one' {
        $script:Compliance = @(
            (New-Policy 'Old' 'iosCompliancePolicy' @{ osMinimumVersion = '17.0' }),
            (New-Policy 'Unset' 'macOSCompliancePolicy' @{ osMinimumVersion = $null }),
            (New-Policy 'Current' 'iosCompliancePolicy' @{ osMinimumVersion = '18.7.11' }),
            (New-Policy 'Ahead' 'iosCompliancePolicy' @{ osMinimumVersion = '26.0' })
        )

        $Prepared = Get-CIPPBaselineIntuneMinimumOSVersionState -Item (New-OSItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @(
            'Old (iOS compliance policy): minimum OS version is 17.0, should be 18.7.11',
            'Unset (macOS compliance policy): minimum OS version is not set, should be 18.7.11'
        )
        $Target = @($Prepared.Current.targets).Where({ $_.uri -eq 'deviceManagement/deviceCompliancePolicies/id-Old' })[0]
        $Target.body.'@odata.type' | Should -Be '#microsoft.graph.iosCompliancePolicy'
        $Target.body.osMinimumVersion | Should -Be '18.7.11'
    }

    It 'only writes the Android setting that is behind' {
        $script:Compliance = @(New-Policy 'Droid' 'androidDeviceOwnerCompliancePolicy' @{ osMinimumVersion = '14.0'; minAndroidSecurityPatchLevel = '2026-06-01' })

        $Prepared = Get-CIPPBaselineIntuneMinimumOSVersionState -Item (New-OSItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('Droid (Android compliance policy): minimum security patch level is 2026-06-01, should be 2026-10-01')
        @($Prepared.Current.targets)[0].body.PSObject.Properties.Name | Should -Be @('@odata.type', 'minAndroidSecurityPatchLevel')
    }

    It 'sets the required and the warning version on app protection policies' {
        $script:AppProtection = @(
            (New-Policy 'MAM' 'iosManagedAppProtection' @{ minimumRequiredOsVersion = '18.7.11'; minimumWarningOsVersion = '18.7.11' }),
            (New-Policy 'Config' 'targetedManagedAppConfiguration')
        )

        $Prepared = Get-CIPPBaselineIntuneMinimumOSVersionState -Item (New-OSItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('MAM (iOS app protection policy): warning OS version is 18.7.11, should be 18.7.12')
        $Target = @($Prepared.Current.targets)[0]
        $Target.uri | Should -Be 'deviceAppManagement/iosManagedAppProtections/id-MAM'
        $Target.body.minimumWarningOsVersion | Should -Be '18.7.12'
        $Target.body.PSObject.Properties.Name | Should -Not -Contain 'minimumRequiredOsVersion'
    }

    It 'leaves excluded policies alone, by part of the name or by wildcard' {
        $script:Compliance = @(
            (New-Policy 'Kiosk iPads' 'iosCompliancePolicy' @{ osMinimumVersion = '15.0' }),
            (New-Policy 'Legacy - Warehouse' 'iosCompliancePolicy' @{ osMinimumVersion = '15.0' }),
            (New-Policy 'Corporate' 'iosCompliancePolicy' @{ osMinimumVersion = '15.0' })
        )
        $Item = New-OSItem @{ excludedPolicies = @([pscustomobject]@{ label = 'kiosk'; value = 'kiosk' }, [pscustomobject]@{ label = 'Legacy*'; value = 'Legacy*' }) }

        $Prepared = Get-CIPPBaselineIntuneMinimumOSVersionState -Item $Item -TenantFilter $script:Tenant

        @($Prepared.Current.targets).uri | Should -Be @('deviceManagement/deviceCompliancePolicies/id-Corporate')
    }

    It 'skips a platform or policy type that is switched off' {
        $script:Compliance = @((New-Policy 'Phones' 'iosCompliancePolicy' @{ osMinimumVersion = '15.0' }), (New-Policy 'Laptops' 'windows10CompliancePolicy' @{ osMinimumVersion = '10.0.19045.0' }))
        $script:AppProtection = @(New-Policy 'MAM' 'iosManagedAppProtection')

        $Prepared = Get-CIPPBaselineIntuneMinimumOSVersionState -Item (New-OSItem @{ iOS = $false }) -TenantFilter $script:Tenant
        @($Prepared.Current.targets).uri | Should -Be @('deviceManagement/deviceCompliancePolicies/id-Laptops')

        $Prepared = Get-CIPPBaselineIntuneMinimumOSVersionState -Item (New-OSItem @{ compliancePolicies = $false }) -TenantFilter $script:Tenant
        @($Prepared.Current.targets).uri | Should -Be @('deviceAppManagement/iosManagedAppProtections/id-MAM')
    }

    It 'reports why it cannot grade when the release list is unavailable' {
        Mock Get-CIPPOSLifecycle { throw 'Could not get the ios release list from endoflife.date: timeout' }
        $script:Compliance = @(New-Policy 'Old' 'iosCompliancePolicy' @{ osMinimumVersion = '17.0' })

        $Prepared = Get-CIPPBaselineIntuneMinimumOSVersionState -Item (New-OSItem) -TenantFilter $script:Tenant

        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -Match 'endoflife.date'
    }
}

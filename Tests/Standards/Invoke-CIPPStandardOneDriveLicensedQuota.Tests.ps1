# Pester tests for Invoke-CIPPStandardOneDriveLicensedQuota
#
# Covers the entitlement rules the standard encodes: only enabled users with a qualifying
# service plan count, the Microsoft five-user minimum gates every mode, quotas at or above
# 5 TB (including support-raised 25 TB drives) are never touched, unprovisioned OneDrives
# are skipped, and remediation targets the personal site URL with the 5 TB quota.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardOneDriveLicensedQuota.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardOneDriveLicensedQuota.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift in the standard fail loudly here instead of silently
    # landing in $args.
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $RequiredCapabilities, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $NoAuthCheck, $skipTokenCache, [switch]$ComplexFilter, $CountOnly) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $NoAuthCheck, $scope, $asapp, $Requests, $NoPaginateIds, $Version, $Headers) }
    function Set-CIPPSPOSiteBulk { [CmdletBinding()] param($TenantFilter, $Sites, $MaxConcurrency, $MaxRetries, [switch]$UseCertificate) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    # Script scope: Pester 5 evaluates the Describe body at discovery, so plain variables
    # declared there are not in scope inside It blocks or mocks at run time.
    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:SharePointPlan2 = '5dbe027f-2339-4123-9542-606e4d348a72'
    $script:OneDrivePlan2 = 'afcafa6a-d966-4462-918c-ec0b4e0fe642'
    $script:OneTB = 1TB
    $script:FiveTB = 5TB

    function script:New-TestUser {
        param([string]$Id, [string]$Upn, [bool]$Enabled = $true, [string]$PlanId = $script:SharePointPlan2, [string]$PlanStatus = 'Enabled')
        [pscustomobject]@{
            id                = $Id
            userPrincipalName = $Upn
            accountEnabled    = $Enabled
            assignedPlans     = @([pscustomobject]@{ servicePlanId = $PlanId; capabilityStatus = $PlanStatus })
        }
    }

    function script:New-DriveResponse {
        param([string]$Id, [int64]$Total, [int]$Status = 200)
        if ($Status -ne 200) {
            return [pscustomobject]@{ id = $Id; status = $Status; body = [pscustomobject]@{ error = @{ code = 'ResourceNotFound' } } }
        }
        $Upn = ($Id -replace '-', '')
        [pscustomobject]@{
            id     = $Id
            status = 200
            body   = [pscustomobject]@{
                webUrl = "https://contoso-my.sharepoint.com/personal/$($Upn)_contoso_com/Documents"
                quota  = [pscustomobject]@{ total = $Total; used = 1GB }
            }
        }
    }
}

Describe 'Invoke-CIPPStandardOneDriveLicensedQuota' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:setCalls = [System.Collections.Generic.List[object]]::new()
        $script:bulkRequests = $null

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $LogData)
            $script:logs.Add(@{ Message = $message; Sev = $sev })
        }
        # The standard raises quotas through one concurrent Set-CIPPSPOSiteBulk fan-out rather than
        # a Set-CIPPSPOSite call per drive. Expand its -Sites back into the per-site records the
        # assertions read, and grade every site a success unless a test overrides this mock.
        Mock -CommandName Set-CIPPSPOSiteBulk -MockWith {
            param($TenantFilter, $Sites, $MaxConcurrency, $MaxRetries, [switch]$UseCertificate)
            @(foreach ($Site in $Sites) {
                    $script:setCalls.Add(@{ SiteUrl = $Site.SiteUrl; Properties = $Site.Properties })
                    [pscustomobject]@{ SiteUrl = $Site.SiteUrl; Success = $true; Error = $null }
                })
        }
    }

    Context 'six entitled users with mixed quotas' {
        BeforeEach {
            # u1/u5 at the 1 TB default, u6 manually bumped to 2 TB, u2 already at 5 TB,
            # u3 raised to 25 TB by support, u4 has no OneDrive provisioned. u7 is disabled
            # and u8 holds no qualifying plan, so neither may generate a drive lookup.
            Mock -CommandName New-GraphGetRequest -MockWith {
                @(
                    script:New-TestUser -Id 'u1' -Upn 'u1@contoso.com'
                    script:New-TestUser -Id 'u2' -Upn 'u2@contoso.com'
                    script:New-TestUser -Id 'u3' -Upn 'u3@contoso.com' -PlanId $script:OneDrivePlan2
                    script:New-TestUser -Id 'u4' -Upn 'u4@contoso.com'
                    script:New-TestUser -Id 'u5' -Upn 'u5@contoso.com'
                    script:New-TestUser -Id 'u6' -Upn 'u6@contoso.com'
                    script:New-TestUser -Id 'u7' -Upn 'u7@contoso.com' -Enabled $false
                    script:New-TestUser -Id 'u8' -Upn 'u8@contoso.com' -PlanId '13696edf-5a08-49f6-8134-03083ed8ba30'
                )
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                param($tenantid, $Requests, $asapp)
                $script:bulkRequests = @($Requests)
                @(
                    script:New-DriveResponse -Id 'u1' -Total $script:OneTB
                    script:New-DriveResponse -Id 'u2' -Total $script:FiveTB
                    script:New-DriveResponse -Id 'u3' -Total (25TB)
                    script:New-DriveResponse -Id 'u4' -Status 404
                    script:New-DriveResponse -Id 'u5' -Total $script:OneTB
                    script:New-DriveResponse -Id 'u6' -Total (2TB)
                )
            }
        }

        It 'only looks up drives for enabled users holding a qualifying plan' {
            Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ remediate = $true }

            $script:bulkRequests.Count | Should -Be 6
            $script:bulkRequests.id | Should -Not -Contain 'u7' -Because 'disabled accounts are excluded'
            $script:bulkRequests.id | Should -Not -Contain 'u8' -Because 'OneDrive Plan 1 carries no 5 TB entitlement'
        }

        It 'raises only the drives below 5 TB and targets the personal site URL' {
            Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ remediate = $true }

            $script:setCalls.Count | Should -Be 3
            $script:setCalls.SiteUrl | Should -Contain 'https://contoso-my.sharepoint.com/personal/u1_contoso_com'
            $script:setCalls.SiteUrl | Should -Contain 'https://contoso-my.sharepoint.com/personal/u5_contoso_com'
            $script:setCalls.SiteUrl | Should -Contain 'https://contoso-my.sharepoint.com/personal/u6_contoso_com'
            foreach ($Call in $script:setCalls) {
                $Call.SiteUrl | Should -Not -Match '/Documents$' -Because 'the quota is set on the site, not the document library'
                $Call.Properties.StorageMaximumLevel | Should -Be 5242880
                $Call.Properties.StorageWarningLevel | Should -Be 4718592
            }
        }

        It 'never touches drives at or above 5 TB, including support-raised ones' {
            Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ remediate = $true }

            $script:setCalls.SiteUrl | Should -Not -Contain 'https://contoso-my.sharepoint.com/personal/u2_contoso_com'
            $script:setCalls.SiteUrl | Should -Not -Contain 'https://contoso-my.sharepoint.com/personal/u3_contoso_com'
        }

        It 'alerts with the count of accounts below quota' {
            Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ alert = $true }

            Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter { $message -match '\b3\b' }
            $script:setCalls.Count | Should -Be 0 -Because 'alert mode must not remediate'
        }

        It 'reports the offending accounts against an empty expected list' {
            Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ report = $true }

            Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                $FieldName -eq 'standards.OneDriveLicensedQuota' -and
                @($CurrentValue.OneDriveBelowLicensedQuota).Count -eq 3 -and
                @($ExpectedValue.OneDriveBelowLicensedQuota).Count -eq 0
            }
        }

        It 'continues with the remaining drives when one CSOM update fails' {
            Mock -CommandName Set-CIPPSPOSiteBulk -MockWith {
                param($TenantFilter, $Sites, $MaxConcurrency, $MaxRetries, [switch]$UseCertificate)
                @(foreach ($Site in $Sites) {
                        $script:setCalls.Add(@{ SiteUrl = $Site.SiteUrl; Properties = $Site.Properties })
                        if ($Site.SiteUrl -match 'u1_contoso_com') {
                            [pscustomobject]@{ SiteUrl = $Site.SiteUrl; Success = $false; Error = 'Access denied.' }
                        } else {
                            [pscustomobject]@{ SiteUrl = $Site.SiteUrl; Success = $true; Error = $null }
                        }
                    })
            }

            { Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ remediate = $true } } |
                Should -Not -Throw

            $script:setCalls.Count | Should -Be 3
            $Errors = @($script:logs | Where-Object { $_.Sev -eq 'Error' })
            $Errors.Count | Should -Be 1
            $Errors[0].Message | Should -Match 'u1@contoso\.com'
        }
    }

    Context 'fewer than five entitled users' {
        BeforeEach {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @(
                    script:New-TestUser -Id 'u1' -Upn 'u1@contoso.com'
                    script:New-TestUser -Id 'u2' -Upn 'u2@contoso.com'
                    script:New-TestUser -Id 'u3' -Upn 'u3@contoso.com'
                    script:New-TestUser -Id 'u4' -Upn 'u4@contoso.com'
                )
            }
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'must not be called' }
        }

        It 'does not look up drives, remediate or alert' {
            { Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true } } |
                Should -Not -Throw

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            $script:setCalls.Count | Should -Be 0
            Should -Invoke Write-StandardsAlert -Times 0 -Exactly
        }

        It 'reports as compliant so the drift comparison does not go stale' {
            Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ report = $true }

            Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                @($CurrentValue.OneDriveBelowLicensedQuota).Count -eq 0
            }
        }
    }

    Context 'license gate' {
        It 'stops before any Graph call when the tenant lacks the capability' {
            Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'must not be called' }

            { Invoke-CIPPStandardOneDriveLicensedQuota -Tenant $script:Tenant -Settings @{ remediate = $true } } |
                Should -Not -Throw

            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        }
    }
}

# Pester tests for Invoke-CIPPStandardSPOVersionControl
#
# Issue #503: with automatic version trimming enabled the standard still wrote null placeholders
# for MajorVersionLimit / ExpireVersionsAfterDays into the expected object while the current
# object carried the tenant-managed numbers. The compare report and drift detection grade the
# two objects as a whole, so every auto-trim tenant showed as non-compliant even though the
# standard itself considered the state correct. In auto-trim mode only the trim flag is graded.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardSPOVersionControl.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardSPOVersionControl.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Get-CIPPSPOTenant { [CmdletBinding()] param($TenantFilter, [switch]$UseCertificate) }
    function Set-CIPPSPOTenant { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject, $MethodName, $MethodParameters, [switch]$UseCertificate) }
    function Set-CIPPSPOSiteBulk { [CmdletBinding()] param($TenantFilter, $Sites, [switch]$UseCertificate) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $NoAuthCheck, $skipTokenCache) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $Tenant2, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardSPOVersionControl report' {
    BeforeEach {
        $script:Compare = $null
        $script:Bpa = $null
        $script:Alerts = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CIPPSPOTenant -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith {
            param($message, $object, $tenant, $standardName, $standardId)
            $script:Alerts.Add($message)
        }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter)
            $script:Compare = @{ FieldName = $FieldName; Current = $CurrentValue; Expected = $ExpectedValue }
        }
        Mock -CommandName Add-CIPPBPAField -MockWith {
            param($FieldName, $FieldValue, $StoreAs, $Tenant)
            $script:Bpa = $FieldValue
        }
    }

    Context 'automatic trimming desired' {
        BeforeEach {
            # A tenant with auto-trim on still reports the limits SharePoint manages for it.
            Mock -CommandName Get-CIPPSPOTenant -MockWith {
                [pscustomobject]@{
                    _ObjectIdentity_                = 'id'
                    TenantFilter                    = $script:Tenant
                    EnableAutoExpirationVersionTrim = $true
                    MajorVersionLimit               = 500
                    ExpireVersionsAfterDays         = 30
                }
            }
        }

        It 'grades only the trim flag so tenant-managed limits are not drift' {
            Invoke-CIPPStandardSPOVersionControl -Tenant $script:Tenant -Settings @{ EnableAutoTrim = $true; report = $true }

            $script:Compare.FieldName | Should -Be 'standards.SPOVersionControl'
            @($script:Compare.Current.PSObject.Properties.Name) | Should -Be @('EnableAutoExpirationVersionTrim')
            @($script:Compare.Expected.PSObject.Properties.Name) | Should -Be @('EnableAutoExpirationVersionTrim')
            $script:Compare.Current.EnableAutoExpirationVersionTrim | Should -BeTrue
            $script:Compare.Expected.EnableAutoExpirationVersionTrim | Should -BeTrue
            # The same whole-object comparison the report and drift paths perform.
            ($script:Compare.Current | ConvertTo-Json -Compress) | Should -Be ($script:Compare.Expected | ConvertTo-Json -Compress)
            $script:Bpa | Should -BeTrue
        }

        It 'still reports a tenant that has automatic trimming off' {
            Mock -CommandName Get-CIPPSPOTenant -MockWith {
                [pscustomobject]@{
                    _ObjectIdentity_                = 'id'
                    TenantFilter                    = $script:Tenant
                    EnableAutoExpirationVersionTrim = $false
                    MajorVersionLimit               = 500
                    ExpireVersionsAfterDays         = 0
                }
            }

            Invoke-CIPPStandardSPOVersionControl -Tenant $script:Tenant -Settings @{ EnableAutoTrim = $true; report = $true; alert = $true }

            $script:Compare.Current.EnableAutoExpirationVersionTrim | Should -BeFalse
            $script:Compare.Expected.EnableAutoExpirationVersionTrim | Should -BeTrue
            $script:Bpa | Should -BeFalse
            $script:Alerts.Count | Should -Be 1
            $script:Alerts[0] | Should -Match 'managed by Microsoft'
            $script:Alerts[0] | Should -Not -Match 'Expected: .*MajorVersionLimit='
        }

        It 'does not write when the tenant already trims automatically' {
            Invoke-CIPPStandardSPOVersionControl -Tenant $script:Tenant -Settings @{ EnableAutoTrim = $true; remediate = $true }

            Should -Invoke -CommandName Set-CIPPSPOTenant -Times 0 -Exactly
        }
    }

    Context 'fixed limits desired' {
        It 'grades the flag and both limits' {
            Mock -CommandName Get-CIPPSPOTenant -MockWith {
                [pscustomobject]@{
                    _ObjectIdentity_                = 'id'
                    TenantFilter                    = $script:Tenant
                    EnableAutoExpirationVersionTrim = $false
                    MajorVersionLimit               = 50
                    ExpireVersionsAfterDays         = 365
                }
            }

            Invoke-CIPPStandardSPOVersionControl -Tenant $script:Tenant -Settings @{ EnableAutoTrim = $false; MajorVersionLimit = 50; ExpireVersionsAfterDays = 365; report = $true }

            @($script:Compare.Expected.PSObject.Properties.Name | Sort-Object) | Should -Be @('EnableAutoExpirationVersionTrim', 'ExpireVersionsAfterDays', 'MajorVersionLimit')
            $script:Compare.Expected.EnableAutoExpirationVersionTrim | Should -BeFalse
            $script:Compare.Expected.MajorVersionLimit | Should -Be 50
            $script:Compare.Expected.ExpireVersionsAfterDays | Should -Be 365
            ($script:Compare.Current | ConvertTo-Json -Compress) | Should -Be ($script:Compare.Expected | ConvertTo-Json -Compress)
            $script:Bpa | Should -BeTrue
        }

        It 'reports a limit that differs from the configured one' {
            Mock -CommandName Get-CIPPSPOTenant -MockWith {
                [pscustomobject]@{
                    _ObjectIdentity_                = 'id'
                    TenantFilter                    = $script:Tenant
                    EnableAutoExpirationVersionTrim = $false
                    MajorVersionLimit               = 500
                    ExpireVersionsAfterDays         = 365
                }
            }

            Invoke-CIPPStandardSPOVersionControl -Tenant $script:Tenant -Settings @{ EnableAutoTrim = $false; MajorVersionLimit = 50; ExpireVersionsAfterDays = 365; report = $true }

            $script:Compare.Current.MajorVersionLimit | Should -Be 500
            $script:Compare.Expected.MajorVersionLimit | Should -Be 50
            $script:Bpa | Should -BeFalse
        }
    }
}

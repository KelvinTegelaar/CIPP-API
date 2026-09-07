# Pester tests for Invoke-CIPPStandardQuarantineRequestAlert
#
# The standard manages a CIPP-owned Protection Alert ('CIPP User requested to release a quarantined
# message'). The regression these tests guard against: report/compliance was computed from a snapshot
# read BEFORE remediation, so a freshly created or updated alert still reported its old (empty)
# recipients until the next scheduled run - which the tenant saw as "force ran, nothing changed".
# The fix re-reads the live state after remediating so the compare field reflects what was applied.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardQuarantineRequestAlert.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardQuarantineRequestAlert.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams, [switch]$Compliance, $UseSystemMailbox) }
    function Write-LogMessage { [CmdletBinding()] param($API, $Tenant, $Message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:PolicyName = 'CIPP User requested to release a quarantined message'
    $script:NotifyUser = 'helpdesk@dpndbl.com'
}

Describe 'Invoke-CIPPStandardQuarantineRequestAlert' {
    BeforeEach {
        # $script:alertObj models the tenant's live Protection Alert: $null = it does not exist.
        $script:alertObj = $null
        $script:compareFields = [System.Collections.Generic.List[object]]::new()
        $script:bpaFields = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Add-CIPPBPAField -MockWith {
            param($FieldName, $FieldValue, $StoreAs, $Tenant)
            $script:bpaFields.Add([pscustomobject]@{ Field = $FieldName; FieldValue = $FieldValue })
        }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter)
            $script:compareFields.Add([pscustomobject]@{ Field = $FieldName; Current = $CurrentValue; Expected = $ExpectedValue })
        }
        # Stateful EXO mock: reads reflect the current alert; writes mutate it, so a re-read after
        # remediation sees the applied change.
        Mock -CommandName New-ExoRequest -MockWith {
            param($tenantid, $cmdlet, $cmdParams, [switch]$Compliance, $UseSystemMailbox)
            switch ($cmdlet) {
                'Get-ProtectionAlert' { return $script:alertObj }
                'New-ProtectionAlert' { $script:alertObj = [pscustomobject]@{ Name = $cmdParams.name; NotifyUser = @($cmdParams.NotifyUser) }; return }
                'Set-ProtectionAlert' { $script:alertObj = [pscustomobject]@{ Name = $cmdParams.Identity; NotifyUser = @($cmdParams.NotifyUser) }; return }
                'Remove-ProtectionAlert' { $script:alertObj = $null; return }
                default { return }
            }
        }
    }

    It 'reports the freshly created alert as compliant in the same run' {
        # Core regression: with no alert present, a remediate+report run must create the alert AND
        # report the applied recipients as compliant - not the pre-remediation empty snapshot.
        Invoke-CIPPStandardQuarantineRequestAlert -Tenant $script:Tenant -Settings @{
            NotifyUser = $script:NotifyUser
            state      = 'enabled'
            remediate  = $true
            report     = $true
        }

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-ProtectionAlert' }
        $script:compareFields.Count | Should -Be 1
        $script:compareFields[0].Current.NotifyUser | Should -Contain $script:NotifyUser
        $script:bpaFields[0].FieldValue | Should -BeTrue
    }

    It 'updates recipients on an existing alert and reports the applied value' {
        $script:alertObj = [pscustomobject]@{ Name = $script:PolicyName; NotifyUser = @('old@contoso.com') }

        Invoke-CIPPStandardQuarantineRequestAlert -Tenant $script:Tenant -Settings @{
            NotifyUser = $script:NotifyUser
            state      = 'enabled'
            remediate  = $true
            report     = $true
        }

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Set-ProtectionAlert' }
        $script:compareFields[0].Current.NotifyUser | Should -Contain $script:NotifyUser
        $script:bpaFields[0].FieldValue | Should -BeTrue
    }

    It 'reports an existing correctly configured alert as compliant without writing' {
        $script:alertObj = [pscustomobject]@{ Name = $script:PolicyName; NotifyUser = @($script:NotifyUser) }

        Invoke-CIPPStandardQuarantineRequestAlert -Tenant $script:Tenant -Settings @{
            NotifyUser = $script:NotifyUser
            state      = 'enabled'
            report     = $true
        }

        Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -in @('New-ProtectionAlert', 'Set-ProtectionAlert') }
        $script:compareFields[0].Current.NotifyUser | Should -Contain $script:NotifyUser
        $script:bpaFields[0].FieldValue | Should -BeTrue
    }

    It 'writes Current and Expected as matching arrays when compliant' {
        # Compliance is decided by CurrentValue -eq ExpectedValue, so both sides must carry the same
        # shape. A single-element Expected must stay an array (a bare @() around an if-expression would
        # unroll it to a scalar and never match the array-shaped Current value).
        $script:alertObj = [pscustomobject]@{ Name = $script:PolicyName; NotifyUser = @($script:NotifyUser) }

        Invoke-CIPPStandardQuarantineRequestAlert -Tenant $script:Tenant -Settings @{
            NotifyUser = $script:NotifyUser
            state      = 'enabled'
            report     = $true
        }

        $Current = $script:compareFields[0].Current.NotifyUser
        $Expected = $script:compareFields[0].Expected.NotifyUser
        ($Current -is [array]) | Should -BeTrue
        ($Expected -is [array]) | Should -BeTrue
        ($Current -join '|') | Should -Be ($Expected -join '|')
    }

    It 'treats an alert with an unexpected extra recipient as non-compliant' {
        # Exact-set semantics: an address CIPP did not configure is drift, even though the configured
        # address is present.
        $script:alertObj = [pscustomobject]@{ Name = $script:PolicyName; NotifyUser = @($script:NotifyUser, 'extra@contoso.com') }

        Invoke-CIPPStandardQuarantineRequestAlert -Tenant $script:Tenant -Settings @{
            NotifyUser = $script:NotifyUser
            state      = 'enabled'
            report     = $true
        }

        $script:bpaFields[0].FieldValue | Should -BeFalse
        $script:compareFields[0].Current.NotifyUser | Should -Contain 'extra@contoso.com'
    }

    It 'reports a missing alert as non-compliant with no recipients' {
        Invoke-CIPPStandardQuarantineRequestAlert -Tenant $script:Tenant -Settings @{
            NotifyUser = $script:NotifyUser
            state      = 'enabled'
            report     = $true
        }

        $script:bpaFields[0].FieldValue | Should -BeFalse
        @($script:compareFields[0].Current.NotifyUser) | Should -BeNullOrEmpty
    }

    It 'removes the alert and reports compliant when state is removed' {
        $script:alertObj = [pscustomobject]@{ Name = $script:PolicyName; NotifyUser = @($script:NotifyUser) }

        Invoke-CIPPStandardQuarantineRequestAlert -Tenant $script:Tenant -Settings @{
            state     = 'removed'
            remediate = $true
            report    = $true
        }

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Remove-ProtectionAlert' }
        $script:bpaFields[0].FieldValue | Should -BeTrue
    }

    It 'skips everything when the tenant is not licensed for Exchange' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }

        Invoke-CIPPStandardQuarantineRequestAlert -Tenant $script:Tenant -Settings @{
            NotifyUser = $script:NotifyUser
            state      = 'enabled'
            remediate  = $true
            report     = $true
        }

        Should -Invoke New-ExoRequest -Times 0
        $script:compareFields.Count | Should -Be 0
    }
}

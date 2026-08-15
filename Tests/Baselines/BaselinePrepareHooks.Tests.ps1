# Prepare hooks normalize a bespoke read into something the engine can compare. Each of these
# holds a normalization decision that the definition JSON cannot express and that fails
# SILENTLY if it regresses - the standard reports Compliant and never remediates:
#
#   - DeviceRegistrationPolicy lifts three '@odata.type' values to plain properties, because
#     Compare-CIPPIntuneObject skips every property matching '*@OData*'. Compared in place they
#     would be ignored forever. It stays FLAT because the compare reports properties present
#     only on the current side as drift, so a nested shape would flag siblings.
#   - DisableBasicAuthSMTP grades the per-user override list only when the point is DISABLING
#     SMTP AUTH; an operator who deliberately enabled it has not asked for enablements to be
#     stripped.
#   - ActivityBasedTimeout reads the timeout out of a JSON string nested inside the policy
#     JSON, in both the portal/Graph shape and the legacy root shape.
#
# Fixtures go through ConvertFrom-Json on purpose: that is how New-CIPPDbRequest returns cached
# rows (CippJson preserves ConvertFrom-Json's Int64 number semantics) and how the rendered
# expected side arrives. A PowerShell literal would be Int32 and the type-strict compare would
# report drift that production never sees.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineDeviceRegistrationPolicyState.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineDisableBasicAuthSMTPState.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineActivityBasedTimeoutState.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }

    # Mirrors the engine: project Current down to the Expected keys, then compare.
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
}

Describe 'Get-CIPPBaselineDeviceRegistrationPolicyState' {
    BeforeAll {
        $script:Policy = @{
            userDeviceQuota              = 50
            multiFactorAuthConfiguration = 'required'
            localAdminPassword           = @{ isEnabled = $true }
            azureADJoin                  = @{
                isAdminConfigurable = $true
                allowedToJoin       = @{ '@odata.type' = '#microsoft.graph.noDeviceRegistrationMembership' }
                localAdmins         = @{
                    registeringUsers   = @{ '@odata.type' = '#microsoft.graph.allDeviceRegistrationMembership' }
                    enableGlobalAdmins = $true
                }
            }
            azureADRegistration          = @{ isAdminConfigurable = $false; allowedToRegister = @{ '@odata.type' = '#microsoft.graph.allDeviceRegistrationMembership' } }
        } | ConvertTo-Cached
    }
    BeforeEach { Mock New-CIPPDbRequest { @($script:Policy) } }

    It 'lifts every @odata.type membership value to a plain, comparable property' {
        $Current = (Get-CIPPBaselineDeviceRegistrationPolicyState -Item $null -TenantFilter $script:Tenant).Current
        $Current.allowedToJoin | Should -Be '#microsoft.graph.noDeviceRegistrationMembership'
        $Current.allowedToRegister | Should -Be '#microsoft.graph.allDeviceRegistrationMembership'
        $Current.localAdminsRegisteringUsers | Should -Be '#microsoft.graph.allDeviceRegistrationMembership'
    }

    It 'flattens every governed setting to a scalar' {
        # Nested shapes get handed to the compare whole, which then flags current-only
        # siblings such as isAdminConfigurable as drift.
        $Current = (Get-CIPPBaselineDeviceRegistrationPolicyState -Item $null -TenantFilter $script:Tenant).Current
        foreach ($Property in $Current.PSObject.Properties) {
            $Property.Value | Should -Not -BeOfType ([System.Management.Automation.PSCustomObject]) -Because "$($Property.Name) must be a scalar"
        }
    }

    It 'grades a lifted membership value in both directions' {
        # The regression this guards: comparing '@odata.type' in place scores Compliant
        # forever, because Compare-CIPPIntuneObject skips that property name. Both cases are
        # asserted deliberately - a mismatch alone would also pass if the property were
        # always different (e.g. an un-lifted object compared against a string).
        $Current = (Get-CIPPBaselineDeviceRegistrationPolicyState -Item $null -TenantFilter $script:Tenant).Current

        $Mismatched = @{ allowedToRegister = '#microsoft.graph.noDeviceRegistrationMembership' } | ConvertTo-Cached
        (Get-Verdict -Expected $Mismatched -Current $Current).Count | Should -Be 1

        $Matching = @{ allowedToRegister = '#microsoft.graph.allDeviceRegistrationMembership' } | ConvertTo-Cached
        (Get-Verdict -Expected $Matching -Current $Current).Count | Should -Be 0
    }

    It 'scores a matching quota compliant across the JSON round-trip' {
        $Current = (Get-CIPPBaselineDeviceRegistrationPolicyState -Item $null -TenantFilter $script:Tenant).Current
        $Expected = @{ userDeviceQuota = 50 } | ConvertTo-Cached
        (Get-Verdict -Expected $Expected -Current $Current).Count | Should -Be 0
    }

    It 'reports a null Current when nothing is cached' {
        Mock New-CIPPDbRequest { @() }
        (Get-CIPPBaselineDeviceRegistrationPolicyState -Item $null -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineDisableBasicAuthSMTPState' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock New-CIPPDbRequest {
            switch ($Type) {
                'ExoTransportConfig' { @(@{ SmtpClientAuthenticationDisabled = $script:FlagDisabled } | ConvertTo-Cached) }
                'ExoCASMailboxSmtpAuth' { @($script:Overrides | ConvertTo-Cached) }
            }
        }
        $script:FlagDisabled = $true
        $script:Overrides = @()
    }

    It 'reports drift while per-user overrides remain, even with the tenant flag correct' {
        # The defect the audit found in the first conversion: the tenant-wide flag was
        # compliant while individual users kept SMTP AUTH.
        $script:Overrides = @(@{ PrimarySmtpAddress = 'bob@contoso.com' }, @{ PrimarySmtpAddress = 'ann@contoso.com' })
        $Prepared = Get-CIPPBaselineDisableBasicAuthSMTPState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{ disabled = $true } }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'is compliant when the flag is set and no overrides remain' {
        $Prepared = Get-CIPPBaselineDisableBasicAuthSMTPState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{ disabled = $true } }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'does not grade overrides when the operator deliberately enabled SMTP AUTH' {
        $script:FlagDisabled = $false
        $script:Overrides = @(@{ PrimarySmtpAddress = 'bob@contoso.com' })
        $Prepared = Get-CIPPBaselineDisableBasicAuthSMTPState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{ disabled = $false } }) -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'UsersWithSmtpAuthEnabled'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reports a null Current when the transport config is not cached' {
        Mock New-CIPPDbRequest { @() }
        (Get-CIPPBaselineDisableBasicAuthSMTPState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{ disabled = $true } }) -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineActivityBasedTimeoutState' {
    It 'reads the timeout from the portal and Graph shape' {
        $Definition = ConvertTo-Json -Compress -Depth 10 -InputObject @{ ActivityBasedTimeoutPolicy = @{ Version = 1; ApplicationPolicies = @(@{ ApplicationId = 'default'; WebSessionIdleTimeout = '01:00:00' }) } }
        Mock New-CIPPDbRequest { @(@{ id = 'p1'; definition = @($Definition) } | ConvertTo-Cached) }
        (Get-CIPPBaselineActivityBasedTimeoutState -Item $null -TenantFilter $script:Tenant).Current.timeout | Should -Be '01:00:00'
    }

    It 'still reads policies written in the legacy root shape' {
        # Written by an early engine build. Without this fallback those tenants report
        # permanent drift against a policy that is actually correct.
        $Definition = ConvertTo-Json -Compress -Depth 10 -InputObject @{ ActivityBasedTimeoutPolicy = @{ Version = 1; WebSessionIdleTimeout = '06:00:00' } }
        Mock New-CIPPDbRequest { @(@{ id = 'p1'; definition = @($Definition) } | ConvertTo-Cached) }
        (Get-CIPPBaselineActivityBasedTimeoutState -Item $null -TenantFilter $script:Tenant).Current.timeout | Should -Be '06:00:00'
    }

    It 'reports a null Current when nothing is cached' {
        Mock New-CIPPDbRequest { @() }
        (Get-CIPPBaselineActivityBasedTimeoutState -Item $null -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

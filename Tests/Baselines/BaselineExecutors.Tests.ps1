# Executor behaviour. Each of these holds a decision in place that is invisible from the call
# site and expensive to get wrong, because the failure mode is a WRITE to a live tenant:
#
#   - GraphRequest drops a PATCH whose body rendered empty. That is what a step looks like once
#     omitWhenBlank prunes every key from it ("keep the tenant's current value"), and sending {}
#     would be a write the baseline never asked for.
#   - ExoRequest routes a step through the Security & Compliance endpoint only when it asks to.
#     The *-ProtectionAlert family exists nowhere else, and the flag defaults off, so a
#     regression here silently sends compliance cmdlets to Exchange Online.
#   - DeviceRegistrationPolicy merges into a LIVE read. Graph has no PATCH for that object, six
#     standards each own one field of it, and a write that sent only its own field would wipe
#     the other five.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    # Parameter binding is case-insensitive, so one casing per name covers every call site.
    function New-GraphPostRequest { param($tenantid, $uri, $Type, $Body, $AsApp, $ContentType, $AddedHeaders) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $SkipValueExtraction) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox, [switch]$Compliance) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }

    . (Join-Path $Baselines 'Invoke-CIPPBaselineGraphRequest.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineExoRequest.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineDeviceRegistrationPolicy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    # Specs reach an executor already rendered, i.e. as ConvertFrom-Json output. Building the
    # fixtures the same way matters: ConvertFrom-Json yields Int64 where a PowerShell literal
    # yields Int32, and the compare in the wider engine is type-strict.
    function ConvertTo-Spec { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }
}

Describe 'Invoke-CIPPBaselineGraphRequest' {
    BeforeEach { Mock New-GraphPostRequest {} }

    It 'skips a PATCH whose body rendered empty' {
        $Spec = @{ requests = @(@{ method = 'PATCH'; uri = 'admin/people/pronouns'; body = @{} }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 0
    }

    It 'still sends a PATCH that has something to write' {
        $Spec = @{ requests = @(@{ method = 'PATCH'; uri = 'admin/people/pronouns'; body = @{ isEnabledInOrganization = $true } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter { $uri -like '*admin/people/pronouns' }
    }

    It 'does not treat a bodyless POST as nothing to do' {
        # Only PATCH is dropped: a POST with no body can be a legitimate action call.
        $Spec = @{ requests = @(@{ method = 'POST'; uri = 'someAction'; body = @{} }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1
    }

    It 'defaults to app-only and honours a per-step asApp:false' {
        $Spec = @{ requests = @(
                @{ method = 'PATCH'; uri = 'appOnly'; body = @{ a = 1 } },
                @{ method = 'PATCH'; uri = 'delegated'; asApp = $false; body = @{ a = 1 } }
            ) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter { $uri -like '*appOnly' -and $AsApp -eq $true }
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter { $uri -like '*delegated' -and $AsApp -eq $false }
    }

    It 'continues past a failing step only when it says so' {
        Mock New-GraphPostRequest { throw 'already exists' } -ParameterFilter { $uri -like '*first' }
        $Tolerated = @{ requests = @(
                @{ method = 'POST'; uri = 'first'; body = @{ a = 1 }; continueOnError = $true },
                @{ method = 'PATCH'; uri = 'second'; body = @{ a = 1 } }
            ) } | ConvertTo-Spec
        { Invoke-CIPPBaselineGraphRequest -Remediate $Tolerated -TenantFilter $script:Tenant -Current $null } | Should -Not -Throw
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter { $uri -like '*second' }

        $Fatal = @{ requests = @(@{ method = 'POST'; uri = 'first'; body = @{ a = 1 } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineGraphRequest -Remediate $Fatal -TenantFilter $script:Tenant -Current $null } | Should -Throw
    }
}

Describe 'Invoke-CIPPBaselineExoRequest' {
    BeforeEach { Mock New-ExoRequest {} }

    It 'routes a compliance step through the Security and Compliance endpoint' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-ProtectionAlert'; compliance = $true; params = @{ Identity = 'x' } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'Set-ProtectionAlert' -and $Compliance.IsPresent }
    }

    It 'leaves an ordinary step on Exchange Online' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-TransportConfig'; params = @{ SmtpClientAuthenticationDisabled = $true } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { -not $Compliance.IsPresent }
    }

    It 'passes params through as a hashtable of cmdlet arguments' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-HostedOutboundSpamFilterPolicy'; params = @{ Identity = 'Default'; NotifyOutboundSpam = $true } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdParams['Identity'] -eq 'Default' -and $cmdParams['NotifyOutboundSpam'] -eq $true
        }
    }
}

Describe 'Invoke-CIPPBaselineDeviceRegistrationPolicy' {
    BeforeAll {
        function New-SamplePolicy {
            @{
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
                azureADRegistration          = @{
                    isAdminConfigurable = $false
                    allowedToRegister   = @{ '@odata.type' = '#microsoft.graph.allDeviceRegistrationMembership' }
                }
            } | ConvertTo-Spec
        }
    }
    BeforeEach {
        Mock New-GraphGetRequest { New-SamplePolicy }
        Mock New-GraphPostRequest {}
        Mock Write-LogMessage {}
    }

    It 'preserves every field it was not asked to change' {
        # The whole point of the shared executor: six standards write to this one PUT-only
        # object, so a write that sent only its own field would undo the other five.
        $Spec = @{ set = @{ userDeviceQuota = 99 } } | ConvertTo-Spec
        Invoke-CIPPBaselineDeviceRegistrationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter {
            $Sent = $Body | ConvertFrom-Json
            $Sent.userDeviceQuota -eq 99 -and
            $Sent.localAdminPassword.isEnabled -eq $true -and
            $Sent.multiFactorAuthConfiguration -eq 'required' -and
            $Sent.azureADJoin.localAdmins.enableGlobalAdmins -eq $true -and
            $Sent.azureADJoin.allowedToJoin.'@odata.type' -eq '#microsoft.graph.noDeviceRegistrationMembership'
        }
    }

    It 'assigns a nested dot-path verbatim' {
        $Spec = @{ set = @{ 'azureADJoin.allowedToJoin' = @{ '@odata.type' = '#microsoft.graph.allDeviceRegistrationMembership'; users = $null; groups = $null } } } | ConvertTo-Spec
        Invoke-CIPPBaselineDeviceRegistrationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter {
            ($Body | ConvertFrom-Json).azureADJoin.allowedToJoin.'@odata.type' -eq '#microsoft.graph.allDeviceRegistrationMembership'
        }
    }

    It 'merges from a live read rather than the cached row' {
        # Merging a cached object would revert whatever a sibling standard wrote since the
        # last collection - the exact clobbering this executor exists to prevent.
        $Stale = @{ userDeviceQuota = 1; localAdminPassword = @{ isEnabled = $false } } | ConvertTo-Spec
        $Spec = @{ set = @{ userDeviceQuota = 99 } } | ConvertTo-Spec
        Invoke-CIPPBaselineDeviceRegistrationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $Stale
        Should -Invoke New-GraphGetRequest -Times 1
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter {
            ($Body | ConvertFrom-Json).localAdminPassword.isEnabled -eq $true
        }
    }

    It 'skips the write when the branch is not admin-configurable' {
        # Common on Intune-enabled tenants. A tenant fact, not a failure: erroring here would
        # turn most of the fleet red on every run.
        $Spec = @{ requireAdminConfigurable = 'azureADRegistration'; set = @{ 'azureADRegistration.allowedToRegister' = @{ '@odata.type' = '#microsoft.graph.noDeviceRegistrationMembership' } } } | ConvertTo-Spec
        Invoke-CIPPBaselineDeviceRegistrationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*isAdminConfigurable is false*' }
    }

    It 'writes when the branch is admin-configurable' {
        $Spec = @{ requireAdminConfigurable = 'azureADJoin'; set = @{ 'azureADJoin.allowedToJoin' = @{ '@odata.type' = '#microsoft.graph.noDeviceRegistrationMembership' } } } | ConvertTo-Spec
        Invoke-CIPPBaselineDeviceRegistrationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1
    }

    It 'refuses to PUT when the spec asks for no changes' {
        $Spec = @{ set = @{} } | ConvertTo-Spec
        { Invoke-CIPPBaselineDeviceRegistrationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $null } | Should -Throw '*nothing configured*'
        Should -Invoke New-GraphPostRequest -Times 0
    }
}

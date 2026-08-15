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
    function New-GraphBulkRequest { param($tenantid, $scope, $asapp, $Requests, $Version, $Headers, $NoAuthCheck, $NoPaginateIds) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox, [switch]$Compliance) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CIPPDBCacheUsers { param($TenantFilter) }

    . (Join-Path $Baselines 'Invoke-CIPPBaselineGraphRequest.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineExoRequest.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineDeviceRegistrationPolicy.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineGraphBulkSweep.ps1')

    # $batch answers one response per request, keyed by the id the caller supplied.
    function New-BulkSuccess { param($Requests) @($Requests | ForEach-Object { [PSCustomObject]@{ id = $_.id; status = 204 } }) }

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

Describe 'Invoke-CIPPBaselineGraphBulkSweep' {
    BeforeEach {
        Mock New-GraphBulkRequest { New-BulkSuccess -Requests $Requests }
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheUsers {}
    }

    It 'sends one request per offender, with the id spliced into the url' {
        $Current = @{ targets = @(@{ id = 'a-1' }, @{ id = 'b-2' }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ method = 'PATCH'; uri = 'users/%id%'; body = @{ accountEnabled = $false } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            @($Requests).Count -eq 2 -and
            @($Requests)[0].url -eq '/users/a-1' -and @($Requests)[1].url -eq '/users/b-2' -and
            @($Requests)[0].body.accountEnabled -eq $false
        }
    }

    It 'keeps a per-object token its JSON type' {
        # PasswordExpireDisabled carries a per-domain notification window. Sent as the string
        # "14" Graph rejects the body, so the exact-token rule has to survive per-object
        # expansion the same way it does in the engine's render.
        $Current = @{ targets = @(@{ id = 'contoso.com'; passwordNotificationWindowInDays = 14 }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ method = 'PATCH'; uri = 'domains/%id%'; body = @{ passwordValidityPeriodInDays = 2147483647; passwordNotificationWindowInDays = '%passwordNotificationWindowInDays%' } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            @($Requests)[0].body.passwordNotificationWindowInDays -is [int] -or @($Requests)[0].body.passwordNotificationWindowInDays -is [long]
        }
    }

    It 'runs each write group against its own offender set' {
        # StaleEntraDevices disables one set and deletes another in the same pass.
        $Current = @{
            devicesToDisable = @(@{ id = 'd-1' })
            devicesToDelete  = @(@{ id = 'd-2' }, @{ id = 'd-3' })
        } | ConvertTo-Spec
        $Spec = @{ writes = @(
                @{ from = 'devicesToDisable'; method = 'PATCH'; uri = 'devices/%id%'; body = @{ accountEnabled = $false } },
                @{ from = 'devicesToDelete'; method = 'DELETE'; uri = 'devices/%id%' }
            ) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { @($Requests).Count -eq 1 -and @($Requests)[0].method -eq 'PATCH' }
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { @($Requests).Count -eq 2 -and @($Requests)[0].method -eq 'DELETE' }
    }

    It 'omits the body entirely for a DELETE' {
        $Current = @{ targets = @(@{ id = 'app-1' }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ method = 'DELETE'; uri = 'applications/%id%' }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { -not @($Requests)[0].ContainsKey('body') }
    }

    It 'does nothing when there is nothing to sweep' {
        $Current = @{ targets = @() } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ method = 'PATCH'; uri = 'users/%id%'; body = @{ accountEnabled = $false } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphBulkRequest -Times 0
    }

    It 'throws when the prepare hook never produced the named set' {
        # An authoring typo. Silently sweeping nothing would report Remediated forever.
        $Current = @{ targets = @(@{ id = 'a-1' }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ from = 'typo'; method = 'PATCH'; uri = 'users/%id%'; body = @{ a = 1 } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current } | Should -Throw '*no *typo* set*'
    }

    It 'survives a partial failure and reports it' {
        Mock New-GraphBulkRequest {
            @(
                [PSCustomObject]@{ id = '0'; status = 204 }
                [PSCustomObject]@{ id = '1'; status = 403; body = [PSCustomObject]@{ error = [PSCustomObject]@{ message = 'Insufficient privileges' } } }
            )
        }
        $Current = @{ targets = @(@{ id = 'a-1' }, @{ id = 'b-2' }) } | ConvertTo-Spec
        $Spec = @{ refreshCache = @('Users'); writes = @(@{ method = 'PATCH'; uri = 'users/%id%'; body = @{ accountEnabled = $false } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current } | Should -Not -Throw
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*1 of 2 writes failed*' }
        Should -Invoke Set-CIPPDBCacheUsers -Times 1
    }

    It 'throws when every write failed' {
        # A permissions or endpoint problem. Swallowing it reports Remediated forever while
        # nothing on the tenant ever changes.
        Mock New-GraphBulkRequest {
            @($Requests | ForEach-Object { [PSCustomObject]@{ id = $_.id; status = 403; body = [PSCustomObject]@{ error = [PSCustomObject]@{ message = 'Insufficient privileges' } } } })
        }
        $Current = @{ targets = @(@{ id = 'a-1' }, @{ id = 'b-2' }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ method = 'PATCH'; uri = 'users/%id%'; body = @{ accountEnabled = $false } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current } | Should -Throw '*all 2 writes failed*'
    }

    It 'refreshes the named caches after a successful sweep' {
        # Objects just fixed must not read back as drift on the next run.
        $Current = @{ targets = @(@{ id = 'a-1' }) } | ConvertTo-Spec
        $Spec = @{ refreshCache = @('Users'); writes = @(@{ method = 'PATCH'; uri = 'users/%id%'; body = @{ accountEnabled = $false } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPDBCacheUsers -Times 1 -ParameterFilter { $TenantFilter -eq $script:Tenant }
    }
}

Describe 'Number variable rendering' {
    # Live evidence: a saved baseline stores number fields as strings -
    # {"deviceAgeThreshold":"30","deviceDeleteThreshold":"7"} - while switches store real
    # booleans. Spliced raw, "50" never equals a cached 50 under the type-strict compare, so
    # the standard drifts forever and remediation writes a string into a numeric property.
    BeforeAll {
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')

        # The engine's render, reduced to the substitution it performs.
        function Invoke-EngineRender {
            param($Definition, $Template, $Variables)
            $Json = ConvertTo-Json -Compress -Depth 100 -InputObject $Template
            foreach ($Variable in $Variables.PSObject.Properties) {
                $Token = '%{0}%' -f $Variable.Name
                $Value = $Variable.Value
                if ("$(($Definition.variables ?? [PSCustomObject]@{}).($Variable.Name).type)" -eq 'number' -and
                    $Value -is [string] -and "$Value" -match '^-?\d+(\.\d+)?$') {
                    $Value = if ("$Value" -match '^-?\d+$') { [int64]"$Value" } else { [double]"$Value" }
                }
                $Json = $Json.Replace(('"{0}"' -f $Token), (ConvertTo-Json -Compress -Depth 100 -InputObject $Value))
                $Json = $Json.Replace($Token, "$Value")
            }
            $Json | ConvertFrom-Json
        }
        $script:Definition = @{ variables = @{ max = @{ type = 'number' }; label = @{ type = 'textField' } } } | ConvertTo-Spec
    }

    It 'renders a string-saved number as a number, so it matches the cached value' {
        $Expected = Invoke-EngineRender -Definition $script:Definition -Template (@{ userDeviceQuota = '%max%' } | ConvertTo-Spec) -Variables ([PSCustomObject]@{ max = '50' })
        $Current = '{"userDeviceQuota":50}' | ConvertFrom-Json
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Current | Where-Object { $_ }).Count | Should -Be 0
    }

    It 'still reports real drift on a different number' {
        $Expected = Invoke-EngineRender -Definition $script:Definition -Template (@{ userDeviceQuota = '%max%' } | ConvertTo-Spec) -Variables ([PSCustomObject]@{ max = '20' })
        $Current = '{"userDeviceQuota":50}' | ConvertFrom-Json
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Current | Where-Object { $_ }).Count | Should -Be 1
    }

    It 'leaves a non-number variable as the string it is' {
        # Coercing on value shape rather than declared type would turn a textField holding
        # "30" into a number and break string compares.
        $Expected = Invoke-EngineRender -Definition $script:Definition -Template (@{ label = '%label%' } | ConvertTo-Spec) -Variables ([PSCustomObject]@{ label = '30' })
        $Expected.label | Should -BeOfType ([string])
    }
}

Describe 'Invoke-CIPPBaselineExoBulkSweep' {
    BeforeAll {
        . (Join-Path $Baselines 'Invoke-CIPPBaselineExoBulkSweep.ps1')
        function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox, $Anchor, $NoAuthCheck, $Select, $ReturnWithCommand, [switch]$Compliance, [switch]$AsApp) }
        function Set-CIPPDBCacheMailboxes { param($TenantFilter, $Types) }
    }
    BeforeEach {
        Mock New-ExoBulkRequest { @($cmdletArray | ForEach-Object { [PSCustomObject]@{ Success = $true; OperationGuid = $_.OperationGuid } }) }
        Mock Set-CIPPDBCacheMailboxes {}
        Mock Write-LogMessage {}
    }

    It 'builds one cmdlet per offender with the identity spliced in' {
        $Current = @{ targets = @(@{ id = 'a@contoso.com' }, @{ id = 'b@contoso.com' }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ cmdlet = 'Set-Mailbox'; params = @{ Identity = '%id%'; MessageCopyForSentAsEnabled = $true } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoBulkRequest -Times 1 -ParameterFilter {
            @($cmdletArray).Count -eq 2 -and
            @($cmdletArray)[0].CmdletInput.CmdletName -eq 'Set-Mailbox' -and
            @($cmdletArray)[0].CmdletInput.Parameters['Identity'] -eq 'a@contoso.com' -and
            @($cmdletArray)[0].CmdletInput.Parameters['MessageCopyForSentAsEnabled'] -eq $true
        }
    }

    It 'stamps each cmdlet with an OperationGuid so failures are attributable' {
        # Without it New-ExoBulkRequest returns errors with no way to say WHICH mailbox failed.
        $Current = @{ targets = @(@{ id = 'a@contoso.com' }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ cmdlet = 'Set-Mailbox'; params = @{ Identity = '%id%' } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoBulkRequest -Times 1 -ParameterFilter { @($cmdletArray)[0].OperationGuid -eq 'a@contoso.com' }
    }

    It 'does nothing when there is nothing to sweep' {
        $Current = @{ targets = @() } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ cmdlet = 'Set-Mailbox'; params = @{ Identity = '%id%' } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoBulkRequest -Times 0
    }

    It 'throws when the prepare hook never produced the named set' {
        $Current = @{ targets = @(@{ id = 'a' }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ from = 'typo'; cmdlet = 'Set-Mailbox'; params = @{ Identity = '%id%' } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineExoBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current } | Should -Throw '*no *typo* set*'
    }

    It 'survives a partial failure and still refreshes the cache' {
        Mock New-ExoBulkRequest {
            @(
                [PSCustomObject]@{ Success = $true; OperationGuid = 'a@contoso.com' }
                [PSCustomObject]@{ error = 'Mailbox not found'; target = 'b@contoso.com'; OperationGuid = 'b@contoso.com' }
            )
        }
        $Current = @{ targets = @(@{ id = 'a@contoso.com' }, @{ id = 'b@contoso.com' }) } | ConvertTo-Spec
        $Spec = @{ refreshCache = @('Mailboxes'); writes = @(@{ cmdlet = 'Set-Mailbox'; params = @{ Identity = '%id%' } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineExoBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current } | Should -Not -Throw
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*1 of 2 mailbox writes failed*' }
        Should -Invoke Set-CIPPDBCacheMailboxes -Times 1
    }

    It 'throws when every write failed' {
        Mock New-ExoBulkRequest { @($cmdletArray | ForEach-Object { [PSCustomObject]@{ error = 'Access denied'; OperationGuid = $_.OperationGuid } }) }
        $Current = @{ targets = @(@{ id = 'a' }, @{ id = 'b' }) } | ConvertTo-Spec
        $Spec = @{ writes = @(@{ cmdlet = 'Set-Mailbox'; params = @{ Identity = '%id%' } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineExoBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current } | Should -Throw '*all 2 writes failed*'
    }

    It 'passes collector arguments on the refresh, so the umbrella collector stays cheap' {
        # Mailboxes defaults to Types 'All', which fans out permission and calendar batches
        # across every mailbox - never acceptable as a post-sweep refresh.
        $Current = @{ targets = @(@{ id = 'a' }) } | ConvertTo-Spec
        $Spec = @{ refreshCache = @('Mailboxes'); refreshCacheArgs = @{ Mailboxes = @{ Types = 'None' } }
            writes = @(@{ cmdlet = 'Set-Mailbox'; params = @{ Identity = '%id%' } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoBulkSweep -Remediate $Spec -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPDBCacheMailboxes -Times 1 -ParameterFilter { $Types -eq 'None' }
    }
}

Describe 'Invoke-CIPPBaselineQuarantineRequestAlert' {
    # The 'Allow extra addresses' switch decides whether the write preserves recipients it did
    # not add. Getting this wrong silently deletes somebody's notification address.
    BeforeAll {
        . (Join-Path $Baselines 'Invoke-CIPPBaselineQuarantineRequestAlert.ps1')
        $script:AlertName = 'CIPP User requested to release a quarantined message'
    }
    BeforeEach {
        Mock New-ExoRequest { @([PSCustomObject]@{ Name = $script:AlertName; NotifyUser = @('soc@contoso.com', 'dpo@contoso.com') }) } -ParameterFilter { $cmdlet -eq 'Get-ProtectionAlert' }
        Mock New-ExoRequest {} -ParameterFilter { $cmdlet -ne 'Get-ProtectionAlert' }
    }

    It 'keeps recipients it did not add when extras are allowed' {
        $Spec = @{ notifyUser = 'soc@contoso.com'; allowExtraAddresses = $true } | ConvertTo-Spec
        Invoke-CIPPBaselineQuarantineRequestAlert -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'Set-ProtectionAlert' -and
            @($cmdParams['NotifyUser']).Count -eq 2 -and
            @($cmdParams['NotifyUser']) -contains 'dpo@contoso.com'
        }
    }

    It 'adds the configured address when it is missing, without dropping the others' {
        Mock New-ExoRequest { @([PSCustomObject]@{ Name = $script:AlertName; NotifyUser = @('dpo@contoso.com') }) } -ParameterFilter { $cmdlet -eq 'Get-ProtectionAlert' }
        $Spec = @{ notifyUser = 'soc@contoso.com'; allowExtraAddresses = $true } | ConvertTo-Spec
        Invoke-CIPPBaselineQuarantineRequestAlert -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'Set-ProtectionAlert' -and
            @($cmdParams['NotifyUser']) -contains 'soc@contoso.com' -and
            @($cmdParams['NotifyUser']) -contains 'dpo@contoso.com'
        }
    }

    It 'does not duplicate the configured address when it is already present' {
        $Spec = @{ notifyUser = 'soc@contoso.com'; allowExtraAddresses = $true } | ConvertTo-Spec
        Invoke-CIPPBaselineQuarantineRequestAlert -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'Set-ProtectionAlert' -and
            @(@($cmdParams['NotifyUser']) | Where-Object { $_ -eq 'soc@contoso.com' }).Count -eq 1
        }
    }

    It 'enforces the configured address as the only recipient when extras are not allowed' {
        $Spec = @{ notifyUser = 'soc@contoso.com'; allowExtraAddresses = $false } | ConvertTo-Spec
        Invoke-CIPPBaselineQuarantineRequestAlert -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'Set-ProtectionAlert' -and
            @($cmdParams['NotifyUser']).Count -eq 1 -and
            @($cmdParams['NotifyUser'])[0] -eq 'soc@contoso.com'
        }
    }

    It 'creates the alert when it does not exist yet' {
        Mock New-ExoRequest { @() } -ParameterFilter { $cmdlet -eq 'Get-ProtectionAlert' }
        $Spec = @{ notifyUser = 'soc@contoso.com'; allowExtraAddresses = $true } | ConvertTo-Spec
        Invoke-CIPPBaselineQuarantineRequestAlert -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'New-ProtectionAlert' -and $cmdParams['ThreatType'] -eq 'Activity' -and $cmdParams['Name'] -eq $script:AlertName
        }
    }

    It 'refuses to write if the existing alert cannot be read' {
        # Merging into a list we failed to read would delete whatever was on it.
        Mock New-ExoRequest { throw 'compliance endpoint unavailable' } -ParameterFilter { $cmdlet -eq 'Get-ProtectionAlert' }
        $Spec = @{ notifyUser = 'soc@contoso.com'; allowExtraAddresses = $true } | ConvertTo-Spec
        { Invoke-CIPPBaselineQuarantineRequestAlert -Remediate $Spec -TenantFilter $script:Tenant -Current $null } | Should -Throw '*could not read the existing alert*'
        Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -eq 'Set-ProtectionAlert' }
    }
}

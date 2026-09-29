# The per-request tenant scope lives in CIPPCore's module scope ($script:CippAllowedTenantsStorage).
# $script: is per module, so it only works while every reader and writer is a CIPPCore function.
# These tests load the real CIPPCore module and call it from a separate module, the way Craft runs an
# HTTP endpoint (CIPPCore and CIPPHTTP imported side by side), instead of dot-sourcing functions into
# one test scope, which is what hides a reader that has moved to the wrong module.

BeforeAll {
    $script:ModulesRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules'
    Import-Module (Join-Path $script:ModulesRoot 'CIPPCore/CIPPCore.psd1') -Force 3>$null
    $script:Core = Get-Module CIPPCore

    New-Module -Name ScopeProbeHttp -ScriptBlock {
        function Invoke-ScopeProbe {
            param($Type)
            [pscustomobject]@{
                Context = Get-CippRequestContext
                OwnSlot = $script:CippAllowedTenantsStorage
                Rows    = if ($Type) { @(Get-CIPPDbItem -TenantFilter 'allTenants' -Type $Type) }
            }
        }
        Export-ModuleMember -Function Invoke-ScopeProbe
    } | Import-Module

    # The same two statements New-CippCoreRequest runs, executed inside CIPPCore
    function Enter-ProbeScope($Value) {
        & $script:Core { param($V) Initialize-CippRequestContext; $script:CippAllowedTenantsStorage.Value = $V } $Value
    }
}

AfterAll {
    Remove-Module ScopeProbeHttp, CIPPCore -Force -ErrorAction SilentlyContinue
}

Describe 'Request tenant scope across the module boundary' {
    It 'is only read or written by CIPPCore' {
        $Outside = Get-ChildItem $script:ModulesRoot -Recurse -Include '*.ps1', '*.psm1' |
            Where-Object { $_.FullName -notlike (Join-Path $script:ModulesRoot 'CIPPCore*') } |
            Select-String -Pattern 'CippAllowed(Tenants|Groups)Storage' |
            ForEach-Object { '{0}:{1}' -f $_.Path.Substring($script:ModulesRoot.Length + 1), $_.LineNumber }
        $Outside | Should -BeNullOrEmpty -Because 'outside CIPPCore $script: is a different, always-empty variable; use Get-CippRequestContext'
    }

    It 'set in CIPPCore is seen by CIPPCore helpers called from another module' {
        Enter-ProbeScope @('id-a')
        $Probe = Invoke-ScopeProbe
        @($Probe.Context.AllowedTenants) | Should -Be @('id-a')
        $Probe.OwnSlot | Should -BeNullOrEmpty
    }

    It 'keeps a scope entitled to nothing distinct from unrestricted' {
        Enter-ProbeScope @()
        $Probe = Invoke-ScopeProbe
        $null -eq $Probe.Context.AllowedTenants | Should -BeFalse
        @($Probe.Context.AllowedTenants).Count | Should -Be 0
    }

    It 'is cleared by Initialize-CippRequestContext for the next request' {
        Enter-ProbeScope @('id-a')
        Enter-ProbeScope $null
        (Invoke-ScopeProbe).Context.AllowedTenants | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPDbItem allTenants honours the request scope when called from another module' {
    BeforeAll {
        Mock -ModuleName CIPPCore Get-CippTable { @{ Context = 'ctx' } }
        Mock -ModuleName CIPPCore Get-Tenants { @([pscustomobject]@{ customerId = 'id-a'; defaultDomainName = 'a.com' }) }
        Mock -ModuleName CIPPCore Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'MailboxRules-1' } }
    }

    It 'reads only the allowed partitions for a scoped request' {
        Enter-ProbeScope @('id-a')
        $Probe = Invoke-ScopeProbe -Type 'MailboxRules'
        $Probe.Rows.Count | Should -Be 1
        Should -Invoke -ModuleName CIPPCore Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -like "PartitionKey eq 'a.com' and RowKey ge 'MailboxRules-'*" }
        Should -Invoke -ModuleName CIPPCore Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Filter -notlike 'PartitionKey*' }
    }

    It 'reads the table once for an unrestricted request' {
        Enter-ProbeScope $null
        $null = Invoke-ScopeProbe -Type 'MailboxRules'
        Should -Invoke -ModuleName CIPPCore Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -notlike 'PartitionKey*' }
        Should -Invoke -ModuleName CIPPCore Get-Tenants -Times 0 -Exactly
    }
}

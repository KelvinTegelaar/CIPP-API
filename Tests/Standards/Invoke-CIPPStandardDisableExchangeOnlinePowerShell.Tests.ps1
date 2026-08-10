# Pester tests for Invoke-CIPPStandardDisableExchangeOnlinePowerShell
#
# Issue #237: a fully successful run reported "0 out of N" with no per-user errors.
# Set-User returns no body on success, and New-ExoBulkRequest only synthesises a
# { Success = $true } record when the request carried an OperationGuid - so without one
# every success was invisible. The mock below reproduces that contract exactly.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardDisableExchangeOnlinePowerShell.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardDisableExchangeOnlinePowerShell.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $NoAuthCheck, $skipTokenCache) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $Requests, $Version, $AsApp, $NoAuthCheck) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type) }
    function New-ExoBulkRequest { [CmdletBinding()] param($tenantid, $cmdletArray, [switch]$ReturnWithCommand, [switch]$useSystemMailbox, $Anchor) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $Tenant2, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'

    # Mirrors New-ExoBulkRequest's non-ReturnWithCommand contract: a setter emits nothing on
    # success unless the caller supplied an OperationGuid, in which case a synthetic success
    # record is produced. Errors always come back.
    function script:Invoke-FakeExoBulk {
        param($cmdletArray, [string[]]$FailFor = @())
        foreach ($Cmd in @($cmdletArray)) {
            $Identity = $Cmd.CmdletInput.Parameters.Identity
            $Guid = $Cmd.OperationGuid
            if ($FailFor -contains $Identity -or $FailFor -contains $Guid) {
                $Err = [pscustomobject]@{ error = "Could not set user $Identity"; target = $Identity }
                if ($Guid) { $Err | Add-Member -NotePropertyName OperationGuid -NotePropertyValue $Guid -Force }
                $Err
            } elseif ($Guid) {
                [pscustomobject]@{ Success = $true; OperationGuid = $Guid }
            }
            # no OperationGuid + success => nothing emitted, exactly like the real helper
        }
    }
}

Describe 'Invoke-CIPPStandardDisableExchangeOnlinePowerShell remediation' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:sentArray = $null

        $script:Mailboxes = @(
            [pscustomobject]@{ UPN = 'ann@contoso.com'; Guid = '11111111-1111-1111-1111-111111111111'; RemotePowerShellEnabled = $true }
            [pscustomobject]@{ UPN = 'ben@contoso.com'; Guid = '22222222-2222-2222-2222-222222222222'; RemotePowerShellEnabled = $true }
            [pscustomobject]@{ UPN = 'cat@contoso.com'; Guid = $null; RemotePowerShellEnabled = $true }
        )

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-CIPPDbRequest -MockWith { $script:Mailboxes }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $LogData)
            $script:logs.Add(@{ Message = $message; Sev = $sev })
        }
        Mock -CommandName New-ExoBulkRequest -MockWith {
            param($tenantid, $cmdletArray)
            $script:sentArray = @($cmdletArray)
            script:Invoke-FakeExoBulk -cmdletArray $cmdletArray
        }
    }

    It 'counts every user when all of them succeed' {
        Invoke-CIPPStandardDisableExchangeOnlinePowerShell -Tenant $script:Tenant -Settings @{ remediate = $true }

        $Summary = @($script:logs | Where-Object { $_.Message -match 'out of' })
        $Summary.Count | Should -Be 1
        $Summary[0].Message | Should -Match 'for 3 out of 3 users'
    }

    It 'tags every request with an OperationGuid so successes are visible' {
        Invoke-CIPPStandardDisableExchangeOnlinePowerShell -Tenant $script:Tenant -Settings @{ remediate = $true }

        @($script:sentArray).Count | Should -Be 3
        foreach ($Cmd in $script:sentArray) {
            $Cmd.OperationGuid | Should -Not -BeNullOrEmpty
        }
        ($script:sentArray.OperationGuid | Sort-Object) | Should -Be @('ann@contoso.com', 'ben@contoso.com', 'cat@contoso.com')
    }

    It 'logs no error and no short-batch warning on a clean run' {
        Invoke-CIPPStandardDisableExchangeOnlinePowerShell -Tenant $script:Tenant -Settings @{ remediate = $true }

        @($script:logs | Where-Object { $_.Sev -eq 'Error' }).Count | Should -Be 0
        @($script:logs | Where-Object { $_.Message -match 'neither confirmed nor reported' }).Count | Should -Be 0
    }

    It 'reports partial success and names the failed user' {
        Mock -CommandName New-ExoBulkRequest -MockWith {
            param($tenantid, $cmdletArray)
            $script:sentArray = @($cmdletArray)
            script:Invoke-FakeExoBulk -cmdletArray $cmdletArray -FailFor 'ben@contoso.com'
        }

        Invoke-CIPPStandardDisableExchangeOnlinePowerShell -Tenant $script:Tenant -Settings @{ remediate = $true }

        (@($script:logs | Where-Object { $_.Message -match 'out of' })[0]).Message | Should -Match 'for 2 out of 3 users'
        $Errors = @($script:logs | Where-Object { $_.Sev -eq 'Error' })
        $Errors.Count | Should -Be 1
        $Errors[0].Message | Should -Match 'ben@contoso.com'
    }

    It 'falls back to the UPN as Identity when the cached mailbox has no Guid' {
        Invoke-CIPPStandardDisableExchangeOnlinePowerShell -Tenant $script:Tenant -Settings @{ remediate = $true }

        $Cat = $script:sentArray | Where-Object { $_.OperationGuid -eq 'cat@contoso.com' }
        $Cat.CmdletInput.Parameters.Identity | Should -BeExactly 'cat@contoso.com'
        # An empty-string Guid must not be sent as the Identity either.
        foreach ($Cmd in $script:sentArray) {
            $Cmd.CmdletInput.Parameters.Identity | Should -Not -BeNullOrEmpty
        }
    }

    It 'warns when Exchange returns fewer results than users requested' {
        Mock -CommandName New-ExoBulkRequest -MockWith {
            param($tenantid, $cmdletArray)
            $script:sentArray = @($cmdletArray)
            # Only the first user comes back at all.
            [pscustomobject]@{ Success = $true; OperationGuid = 'ann@contoso.com' }
        }

        Invoke-CIPPStandardDisableExchangeOnlinePowerShell -Tenant $script:Tenant -Settings @{ remediate = $true }

        @($script:logs | Where-Object { $_.Message -match 'neither confirmed nor reported' }).Count |
            Should -Be 1 -Because 'silently dropping users is what made #237 undiagnosable'
    }
}

# Pester tests for the coverage guard in Invoke-CIPPStandardcalDefault.
#
# Regression under test: only mailboxes with a cached 'Default' row are graded, so a missing
# mailbox could never enter $NeedsUpdate and an incomplete collection read as a clean sweep.
# On a real tenant 44 of 79 went uncollected; the standard saw 35 rows, all correct, and
# logged the all-clear while 8 of the unseen mailboxes were misconfigured.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardcalDefault.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    # Minimal stubs so Mock has commands to replace during tests.
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, [string[]]$Fields) }
    function Set-CIPPStandardsCompareField { param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Write-StandardsAlert { param($message, $object, $tenant, $standardName, $standardId) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Set-CIPPDBCacheMailboxes { param($TenantFilter) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function New-CalRow {
        param($Upn, $Rights)
        [PSCustomObject]@{ Identity = "$Upn`:\Calendar"; User = 'Default'; AccessRights = @($Rights) }
    }
}

Describe 'Invoke-CIPPStandardcalDefault coverage guard' {
    BeforeEach {
        $script:Messages = [System.Collections.Generic.List[object]]::new()
        $script:Compared = $null

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith { $script:Messages.Add([PSCustomObject]@{ Message = $message; Sev = $sev }) }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { $script:Compared = $CurrentValue }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        # Nothing here may reach Exchange: every case below is a no-drift case.
        Mock -CommandName New-ExoRequest -MockWith { throw 'New-ExoRequest must not be called' }

        # Pester 5 runs a Describe body at discovery, so shared fixtures have to be built here
        # to exist when an It actually runs.
        $script:Settings = @{ permissionLevel = 'Reviewer'; remediate = $true; alert = $true; report = $true }
    }

    It 'reports a clean sweep only when every cached mailbox was graded' {
        Mock -CommandName New-CIPPDbRequest -MockWith {
            if ($Type -eq 'Mailboxes') { @(1..3 | ForEach-Object { [PSCustomObject]@{ UPN = "u$_@x.com" } }) }
            else { @(1..3 | ForEach-Object { New-CalRow -Upn "u$_@x.com" -Rights 'Reviewer' }) }
        }

        Invoke-CIPPStandardcalDefault -Tenant 'contoso.onmicrosoft.com' -Settings $script:Settings

        $script:Compared.state | Should -Be 'Configured correctly'
        @($script:Messages | Where-Object { $_.Sev -eq 'Warning' }).Count | Should -Be 0
        @($script:Messages | Where-Object { $_.Message -like 'All 3 calendars already*' }).Count | Should -Be 1
    }

    It 'does not claim alignment when mailboxes were never evaluated' {
        # 3 mailboxes cached, but only 1 has a Default calendar row - the shape the collector bug
        # produced. Every graded row is already correct, so the old code logged the all-clear.
        Mock -CommandName New-CIPPDbRequest -MockWith {
            if ($Type -eq 'Mailboxes') { @(1..3 | ForEach-Object { [PSCustomObject]@{ UPN = "u$_@x.com" } }) }
            else { @(New-CalRow -Upn 'u1@x.com' -Rights 'Reviewer') }
        }

        Invoke-CIPPStandardcalDefault -Tenant 'contoso.onmicrosoft.com' -Settings $script:Settings

        $script:Compared.state | Should -BeNullOrEmpty
        $script:Compared.UncheckedMailboxes | Should -Be 2
        @($script:Compared.NonCompliantCalendars).Count | Should -Be 0

        $Warnings = @($script:Messages | Where-Object { $_.Sev -eq 'Warning' })
        $Warnings.Count | Should -Be 2   # one from the remediate branch, one from the alert branch
        $Warnings[0].Message | Should -BeLike '*2 of 3 mailboxes have no cached Default calendar permission and were NOT evaluated*'
        $Warnings[0].Message | Should -BeLike '*u2@x.com*'   # names them, not just a count
    }

    It 'does not let a stale row for a deleted mailbox mask an uncovered one' {
        # ghost@x.com was deleted but still has a Default row; u2@x.com is genuinely uncovered.
        # Counts net to 2 - 2 = 0 and read as full coverage; identities see the gap.
        Mock -CommandName New-CIPPDbRequest -MockWith {
            if ($Type -eq 'Mailboxes') { @(1..2 | ForEach-Object { [PSCustomObject]@{ UPN = "u$_@x.com" } }) }
            else { @(New-CalRow -Upn 'u1@x.com' -Rights 'Reviewer'; New-CalRow -Upn 'ghost@x.com' -Rights 'Reviewer') }
        }

        Invoke-CIPPStandardcalDefault -Tenant 'contoso.onmicrosoft.com' -Settings $script:Settings

        $script:Compared.UncheckedMailboxes | Should -Be 1
        @($script:Messages | Where-Object { $_.Sev -eq 'Warning' -and $_.Message -like '*u2@x.com*' }).Count | Should -Be 2
    }

    It 'matches a mailbox whose calendar Identity is an Exchange GUID, not a UPN' {
        # Get-MailboxFolderPermission echoes its own canonical identity, which on the real tenant
        # was the ExternalDirectoryObjectId - without the key fan-out this reads as uncovered.
        Mock -CommandName New-CIPPDbRequest -MockWith {
            if ($Type -eq 'Mailboxes') {
                @([PSCustomObject]@{ UPN = 'u1@x.com'; ExternalDirectoryObjectId = '25a48edf-ef11-423e-aa2d-ce4831b94b51' })
            } else {
                @([PSCustomObject]@{ Identity = '25a48edf-ef11-423e-aa2d-ce4831b94b51:\Calendar'; User = 'Default'; AccessRights = @('Reviewer') })
            }
        }

        Invoke-CIPPStandardcalDefault -Tenant 'contoso.onmicrosoft.com' -Settings $script:Settings

        $script:Compared.state | Should -Be 'Configured correctly'
    }

    It 'still flags real drift, and counts coverage alongside it' {
        Mock -CommandName New-CIPPDbRequest -MockWith {
            if ($Type -eq 'Mailboxes') { @(1..4 | ForEach-Object { [PSCustomObject]@{ UPN = "u$_@x.com" } }) }
            else { @(New-CalRow -Upn 'u1@x.com' -Rights 'Reviewer'; New-CalRow -Upn 'u2@x.com' -Rights 'AvailabilityOnly') }
        }
        Mock -CommandName New-ExoRequest -MockWith { }

        Invoke-CIPPStandardcalDefault -Tenant 'contoso.onmicrosoft.com' -Settings $script:Settings

        @($script:Compared.NonCompliantCalendars).Count | Should -Be 1
        $script:Compared.UncheckedMailboxes | Should -Be 2
    }
}

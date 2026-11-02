# Pester tests for Get-CIPPIntuneAssignTarget
# This function exists to keep the assignment check and the assignment remediation reading the same
# setting the same way. The two flags it returns decide whether a difference is assertable at all,
# so getting them wrong reintroduces exactly the bug it was added for: a deviation that no
# remediation run can clear.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignTarget.ps1')
}

Describe 'Get-CIPPIntuneAssignTarget' {

    Context 'targets the standard owns' {
        It 'reports <Value> as managed and applied' -ForEach @(
            @{ Value = 'allLicensedUsers' }
            @{ Value = 'AllDevices' }
            @{ Value = 'AllDevicesAndUsers' }
            @{ Value = 'customGroup' }
        ) {
            $Result = Get-CIPPIntuneAssignTarget -AssignTo $Value

            $Result.AssignTo | Should -Be $Value
            $Result.Managed | Should -BeTrue
            $Result.Applied | Should -BeTrue
        }

        It 'returns the canonical casing so callers can compare with -eq' {
            (Get-CIPPIntuneAssignTarget -AssignTo 'alldevices').AssignTo | Should -BeExactly 'AllDevices'
            (Get-CIPPIntuneAssignTarget -AssignTo 'CUSTOMGROUP').AssignTo | Should -BeExactly 'customGroup'
        }
    }

    Context "'Do not assign'" {
        It 'is applied but not managed' {
            # Remediation still runs Set-CIPPAssignedPolicy (so exclusions and filters land) but adds
            # no include target, and cannot remove one that is already there.
            $Result = Get-CIPPIntuneAssignTarget -AssignTo 'On'

            $Result.Managed | Should -BeFalse
            $Result.Applied | Should -BeTrue
        }
    }

    Context 'no target configured' {
        It 'reports <Case> as neither applied nor managed' -ForEach @(
            @{ Case = 'null'; Value = $null }
            @{ Case = 'empty string'; Value = '' }
            @{ Case = 'whitespace'; Value = '   ' }
        ) {
            # Set-CIPPIntunePolicy skips the assignment step entirely for these, so nothing about
            # assignments is remediable and nothing may be asserted.
            $Result = Get-CIPPIntuneAssignTarget -AssignTo $Value

            $Result.Managed | Should -BeFalse
            $Result.Applied | Should -BeFalse
        }
    }

    Context 'legacy value shapes' {
        It 'unwraps the { label, value } object older templates carry' {
            $Result = Get-CIPPIntuneAssignTarget -AssignTo ([PSCustomObject]@{
                    label = 'Assign to Custom Group'
                    value = 'customGroup'
                })

            $Result.AssignTo | Should -Be 'customGroup'
            $Result.Managed | Should -BeTrue
        }

        It 'trims surrounding whitespace' {
            (Get-CIPPIntuneAssignTarget -AssignTo ' AllDevices ').Managed | Should -BeTrue
        }

        It 'treats an unrecognised value as applied but not managed' {
            # Unknown means "we do not know what set of targets to expect", which must never become
            # "expect no targets".
            $Result = Get-CIPPIntuneAssignTarget -AssignTo 'somethingElse'

            $Result.Managed | Should -BeFalse
            $Result.Applied | Should -BeTrue
        }
    }
}

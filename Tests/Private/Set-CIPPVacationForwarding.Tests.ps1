# Pester tests for Set-CIPPVacationForwarding.
#
# The mail-forwarding half of Vacation Mode. Like the OOO half it is scheduled twice per vacation,
# an 'Add' at the start and a 'Remove' at the end, so a bug here leaves someone's mail permanently
# redirected after they are back.
#
# Internal forwarding and external forwarding are distinct Exchange settings - -Forward takes a
# recipient in the tenant, -ForwardingSMTPAddress takes an outside address - and picking the wrong
# one silently fails to forward. Each requires its own address to have been supplied.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPVacationForwarding.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPVacationForwarding.ps1 under Modules/' }

    function Set-CIPPForwarding {
        param($UserID, $Username, $TenantFilter, $Headers, $APIName, $Forward, $ForwardingSMTPAddress, $KeepCopy, $Disable)
    }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath
}

Describe 'Set-CIPPVacationForwarding' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CIPPForwarding -MockWith { 'Successfully set forwarding' }
    }

    Context 'Turning forwarding on' {
        It 'forwards to a mailbox inside the tenant' {
            $Result = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com') `
                -ForwardOption 'internalAddress' -ForwardInternal 'cover@contoso.com' -KeepCopy $true

            Should -Invoke Set-CIPPForwarding -Times 1 -Exactly -ParameterFilter {
                $UserID -eq 'sseck@contoso.com' -and
                $Username -eq 'sseck@contoso.com' -and
                $Forward -eq 'cover@contoso.com' -and
                $null -eq $ForwardingSMTPAddress -and
                $KeepCopy -eq $true -and
                $TenantFilter -eq 'contoso.com'
            }
            $Result | Should -Contain 'Successfully set forwarding'
        }

        It 'forwards to an address outside the tenant' {
            $null = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com') `
                -ForwardOption 'ExternalAddress' -ForwardExternal 'cover@partner.com' -KeepCopy $false

            Should -Invoke Set-CIPPForwarding -Times 1 -Exactly -ParameterFilter {
                $ForwardingSMTPAddress -eq 'cover@partner.com' -and
                $null -eq $Forward -and
                $KeepCopy -eq $false
            }
        }

        It 'reports a missing <Option> address instead of silently forwarding nowhere' -ForEach @(
            @{ Option = 'internalAddress'; Extra = @{} }
            @{ Option = 'ExternalAddress'; Extra = @{} }
        ) {
            $Result = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com') -ForwardOption $Option

            Should -Invoke Set-CIPPForwarding -Times 0 -Exactly
            @($Result)[0] | Should -BeLike 'Failed to set forwarding for sseck@contoso.com:*is required for*'
        }

        It 'reports an unsupported forward option' {
            $Result = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com')

            Should -Invoke Set-CIPPForwarding -Times 0 -Exactly
            @($Result)[0] | Should -BeLike '*Unsupported forward option*'
        }
    }

    Context 'Turning forwarding off' {
        It 'disables forwarding regardless of which option was originally used' {
            $Result = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Remove' -Users @('sseck@contoso.com') `
                -ForwardOption 'ExternalAddress' -ForwardExternal 'cover@partner.com'

            Should -Invoke Set-CIPPForwarding -Times 1 -Exactly -ParameterFilter {
                $Disable -eq $true -and
                $null -eq $Forward -and
                $null -eq $ForwardingSMTPAddress
            }
            $Result | Should -Contain 'Successfully set forwarding'
        }

        It 'disables forwarding even with no option supplied at all' {
            # The end-of-vacation task only needs to know who to switch off.
            $null = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Remove' -Users @('sseck@contoso.com')

            Should -Invoke Set-CIPPForwarding -Times 1 -Exactly -ParameterFilter { $Disable -eq $true }
        }
    }

    Context 'Batches of users' {
        It 'sets forwarding for every user in the batch' {
            $Result = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Add' `
                -Users @('one@contoso.com', 'two@contoso.com') -ForwardOption 'internalAddress' -ForwardInternal 'cover@contoso.com'

            Should -Invoke Set-CIPPForwarding -Times 2 -Exactly
            $Result.Count | Should -Be 2
        }

        It 'carries on with the batch when one user fails' {
            Mock -CommandName Set-CIPPForwarding -MockWith { throw 'Mailbox not found' } -ParameterFilter { $UserID -eq 'two@contoso.com' }

            $Result = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Remove' `
                -Users @('one@contoso.com', 'two@contoso.com', 'three@contoso.com')

            Should -Invoke Set-CIPPForwarding -Times 3 -Exactly
            $Result | Should -Contain 'Failed to set forwarding for two@contoso.com: Mailbox not found'
        }

        It 'logs a failure against the tenant at Error severity' {
            Mock -CommandName Set-CIPPForwarding -MockWith { throw 'Mailbox not found' }

            $null = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Remove' -Users @('sseck@contoso.com')

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $Sev -eq 'Error' -and $tenant -eq 'contoso.com' -and $message -like '*Failed to set forwarding for sseck@contoso.com*'
            }
        }

        It 'ignores blank entries in the user list' {
            $null = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Remove' -Users @('one@contoso.com', '', '   ')

            Should -Invoke Set-CIPPForwarding -Times 1 -Exactly
        }

        It 'accepts a single user passed outside an array' {
            $null = Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Remove' -Users 'one@contoso.com'

            Should -Invoke Set-CIPPForwarding -Times 1 -Exactly
        }
    }

    Context 'Guard rails' {
        It 'rejects an action other than Add or Remove' {
            { Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Toggle' -Users @('sseck@contoso.com') } |
                Should -Throw
        }

        It 'rejects an unknown forward option at the parameter boundary' {
            { Set-CIPPVacationForwarding -TenantFilter 'contoso.com' -Action 'Add' -Users @('sseck@contoso.com') -ForwardOption 'carrierPigeon' } |
                Should -Throw
        }
    }
}

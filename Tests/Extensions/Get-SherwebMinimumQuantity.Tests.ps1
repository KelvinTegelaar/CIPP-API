# Pester tests for Get-SherwebMinimumQuantity.
# Sherweb lists, per committed subscription, the quantities it may be decreased to and until when
# (commitmentTerm.committedMinimalQuantities). Once those windows close the quantity is locked until the
# next renewal and any decrease is rejected with a 412 commitment-term-violations error. The helper turns
# that list into the floor that applies today so callers can refuse up front with a plain explanation.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Sherweb/Get-SherwebMinimumQuantity.ps1')

    function New-Subscription {
        param([int]$Quantity = 15, $Minimums, [string]$RenewalDate = '2026-03-01', [switch]$NoCommitment)
        if ($NoCommitment) {
            return [pscustomobject]@{ sku = 'SW-TEST'; quantity = $Quantity; commitmentTerm = $null }
        }
        [pscustomobject]@{
            sku            = 'SW-TEST'
            productName    = 'Microsoft 365 Business Premium'
            quantity       = $Quantity
            commitmentTerm = [pscustomobject]@{
                type                      = 'Monthly'
                termEndDate               = '2026-02-28'
                renewalConfiguration      = [pscustomobject]@{ renewalDate = $RenewalDate; scheduledQuantity = $null }
                committedMinimalQuantities = $Minimums
            }
        }
    }
}

Describe 'Get-SherwebMinimumQuantity' {
    It 'returns nothing for a subscription without a commitment term' {
        Get-SherwebMinimumQuantity -Subscription (New-Subscription -NoCommitment) | Should -BeNullOrEmpty
    }

    It 'returns nothing when Sherweb supplied no committed minimal quantities' {
        Get-SherwebMinimumQuantity -Subscription (New-Subscription -Minimums $null) | Should -BeNullOrEmpty
        Get-SherwebMinimumQuantity -Subscription (New-Subscription -Minimums @()) | Should -BeNullOrEmpty
    }

    It 'uses the lowest quantity whose window is still open' {
        # Sherweb's own example: 10 seats bought 1 Feb, 5 more on 2 Feb -> down to 0 until 8 Feb, down to 10 until 9 Feb.
        $Minimums = @(
            [pscustomobject]@{ committedUntil = '2026-02-08'; quantity = 0 },
            [pscustomobject]@{ committedUntil = '2026-02-09'; quantity = 10 }
        )
        $Result = Get-SherwebMinimumQuantity -Subscription (New-Subscription -Minimums $Minimums) -AsOf ([datetime]'2026-02-03')

        $Result.MinimumQuantity | Should -Be 0
        $Result.AllowedUntil | Should -Be ([datetime]'2026-02-08')
        $Result.TermType | Should -Be 'Monthly'
        $Result.RenewsOn | Should -Be ([datetime]'2026-03-01')
    }

    It 'moves to the next floor once the earlier window has closed' {
        $Minimums = @(
            [pscustomobject]@{ committedUntil = '2026-02-08'; quantity = 0 },
            [pscustomobject]@{ committedUntil = '2026-02-09'; quantity = 10 }
        )
        $Result = Get-SherwebMinimumQuantity -Subscription (New-Subscription -Minimums $Minimums) -AsOf ([datetime]'2026-02-09')

        $Result.MinimumQuantity | Should -Be 10
        $Result.AllowedUntil | Should -Be ([datetime]'2026-02-09')
    }

    It 'locks the quantity at its current value once every window has closed' {
        $Minimums = @([pscustomobject]@{ committedUntil = '2026-02-08'; quantity = 0 })
        $Result = Get-SherwebMinimumQuantity -Subscription (New-Subscription -Quantity 15 -Minimums $Minimums) -AsOf ([datetime]'2026-02-20')

        $Result.MinimumQuantity | Should -Be 15
        $Result.AllowedUntil | Should -BeNullOrEmpty
        $Result.RenewsOn | Should -Be ([datetime]'2026-03-01')
    }

    It 'accepts dates Sherweb returns as DateTime objects as well as strings' {
        $Minimums = @([pscustomobject]@{ committedUntil = [datetime]'2026-02-08'; quantity = 3 })
        $Result = Get-SherwebMinimumQuantity -Subscription (New-Subscription -Minimums $Minimums) -AsOf ([datetime]'2026-02-05')

        $Result.MinimumQuantity | Should -Be 3
    }
}

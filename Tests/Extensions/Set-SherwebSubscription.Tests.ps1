# Pester tests for Set-SherwebSubscription's decrease guard.
# Sherweb rejects quantity decreases on committed (NCE) subscriptions outside the days right after a
# purchase or renewal with an opaque 412 commitment-term-violations body. The setter has to refuse up
# front with an explanation of what is allowed and when, and still let permitted changes through.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context) }
    function Get-Tenants { param($TenantFilter) }
    function Get-ExtensionMapping { param($Extension) }
    function Get-SherwebAuthentication { @{ Authorization = 'Bearer test' } }
    function Get-SherwebCurrentSubscription { param($TenantFilter, $CustomerId, $SKU, $ProductName) }
    function Invoke-RestMethod { param($Uri, $Method, $Headers, $Body, $ContentType) }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Sherweb/Get-SherwebMinimumQuantity.ps1')
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Sherweb/Set-SherwebSubscription.ps1')

    function New-Subscription {
        param([int]$Quantity = 15, $Minimums)
        [pscustomobject]@{
            id             = 'aaaaaaaa-0000-4000-8000-000000000001'
            sku            = 'SW-P-O365-15-M1M'
            productName    = 'Microsoft 365 Business Premium'
            quantity       = $Quantity
            commitmentTerm = [pscustomobject]@{
                type                      = 'Monthly'
                termEndDate               = '2026-11-30'
                renewalConfiguration      = [pscustomobject]@{ renewalDate = '2026-12-01'; scheduledQuantity = $null }
                committedMinimalQuantities = $Minimums
            }
        }
    }
}

Describe 'Set-SherwebSubscription decreases' {
    BeforeEach {
        Mock Invoke-RestMethod { [pscustomobject]@{ trackingId = [pscustomobject]@{ requestTrackingId = 'track' } } }
    }

    It 'refuses a decrease once the commitment has locked the quantity, and says when it next renews' {
        Mock Get-SherwebCurrentSubscription { New-Subscription -Quantity 15 -Minimums @([pscustomobject]@{ committedUntil = '2000-01-08'; quantity = 0 }) }

        $Err = { Set-SherwebSubscription -CustomerId 'cust' -SKU 'SW-P-O365-15-M1M' -Remove 1 } | Should -Throw -PassThru
        $Err.Exception.Message | Should -BeLike '*locked until the term renews*'
        $Err.Exception.Message | Should -BeLike '*2026-12-01*'
        $Err.Exception.Message | Should -BeLike "*Schedule decrease at next renewal*"
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'refuses a decrease below the current floor and names the floor' {
        $Minimums = @([pscustomobject]@{ committedUntil = '2999-01-01'; quantity = 10 })
        Mock Get-SherwebCurrentSubscription { New-Subscription -Quantity 15 -Minimums $Minimums }

        $Err = { Set-SherwebSubscription -CustomerId 'cust' -SKU 'SW-P-O365-15-M1M' -Remove 6 } | Should -Throw -PassThru
        $Err.Exception.Message | Should -BeLike '*only be decreased to 10 license(s) until 2999-01-01, not to 9*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'sends the amendment when the decrease stays at or above the floor' {
        $Minimums = @([pscustomobject]@{ committedUntil = '2999-01-01'; quantity = 10 })
        Mock Get-SherwebCurrentSubscription { New-Subscription -Quantity 15 -Minimums $Minimums }

        $null = Set-SherwebSubscription -CustomerId 'cust' -SKU 'SW-P-O365-15-M1M' -Remove 5

        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*/billing/subscriptions/amendments?customerId=cust' -and
            ($Body | ConvertFrom-Json).subscriptionAmendmentParameters[0].newQuantity -eq 10
        }
    }

    It 'lets Sherweb decide when it published no committed minimal quantities' {
        Mock Get-SherwebCurrentSubscription { New-Subscription -Quantity 15 -Minimums $null }

        $null = Set-SherwebSubscription -CustomerId 'cust' -SKU 'SW-P-O365-15-M1M' -Remove 1

        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            ($Body | ConvertFrom-Json).subscriptionAmendmentParameters[0].newQuantity -eq 14
        }
    }

    It 'never applies the commitment guard to increases' {
        Mock Get-SherwebCurrentSubscription { New-Subscription -Quantity 15 -Minimums @([pscustomobject]@{ committedUntil = '2000-01-08'; quantity = 0 }) }

        $null = Set-SherwebSubscription -CustomerId 'cust' -SKU 'SW-P-O365-15-M1M' -Add 2

        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            ($Body | ConvertFrom-Json).subscriptionAmendmentParameters[0].newQuantity -eq 17
        }
    }
}

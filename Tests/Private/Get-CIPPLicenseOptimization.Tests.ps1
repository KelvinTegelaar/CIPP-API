# Pester tests for Get-CIPPLicenseOptimization — the five-tier waste join and summary math.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPLicenseOptimization.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPLicenseOptimization.ps1 under Modules/' }

    function Get-CIPPLicensePrice { param($SkuId) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }

    . $FunctionPath

    # SKU GUIDs
    $script:E5 = 'c7df2760-2c81-4ef7-b578-5b5392b571df'
    $script:E3 = '6fd2c87f-b296-42f0-b197-1e91e994b900'
    $script:ExP1 = '4b9405b0-7788-4568-add1-99614e613b69'
    $script:ExP2 = '19ec0d23-8335-4cbd-94ac-6050e30712fa'

    function New-Lic { param($SkuId, $Name, $Total, $Used, $PlanIds)
        [pscustomobject]@{
            skuId         = $SkuId
            License       = $Name
            TotalLicenses = "$Total"
            CountUsed     = "$Used"
            ServicePlans  = @($PlanIds | ForEach-Object { [pscustomobject]@{ servicePlanId = $_ } })
        }
    }
    function New-User { param($Upn, $Enabled, $LastSignIn, $Skus, $Type = 'Member', $Resource = $false)
        [pscustomobject]@{
            userPrincipalName = $Upn
            accountEnabled    = $Enabled
            userType          = $Type
            isResourceAccount = $Resource
            signInActivity    = if ($LastSignIn) { [pscustomobject]@{ lastSignInDateTime = $LastSignIn; lastNonInteractiveSignInDateTime = $null } } else { $null }
            assignedLicenses  = @($Skus | ForEach-Object { [pscustomobject]@{ skuId = $_; disabledPlans = @() } })
        }
    }
}

Describe 'Get-CIPPLicenseOptimization' {
    BeforeEach {
        Mock -CommandName Get-CIPPLicensePrice -MockWith {
            @(
                [pscustomobject]@{ skuId = $script:E5; Product_Display_Name = 'Office 365 E5'; MonthlyPrice = 38.0; Currency = 'USD'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:E3; Product_Display_Name = 'Office 365 E3'; MonthlyPrice = 23.0; Currency = 'USD'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:ExP1; Product_Display_Name = 'Exchange Online (Plan 1)'; MonthlyPrice = 4.0; Currency = 'USD'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:ExP2; Product_Display_Name = 'Exchange Online (Plan 2)'; MonthlyPrice = 8.0; Currency = 'USD'; Source = 'Estimate' }
            )
        }

        $script:Recent = (Get-Date).AddDays(-5).ToString('o')
        $script:Old = (Get-Date).AddDays(-200).ToString('o')

        # E3 plan set is a strict superset of Exchange P1's -> P1 is redundant when held together.
        $script:Licenses = @(
            New-Lic $script:E5 'Office 365 E5' 10 8 @('EXCH1', 'SPO', 'TEAMS')
            New-Lic $script:E3 'Office 365 E3' 5 5 @('EXCH1', 'SPO', 'TEAMS')
            New-Lic $script:ExP1 'Exchange Online (Plan 1)' 3 2 @('EXCH1')
        )
        $script:Users = @(
            New-User 'u1@contoso.com' $true $script:Recent @($script:E5)              # tier4: exchange-only on E5
            New-User 'u2@contoso.com' $false $script:Recent @($script:E5)             # tier2: disabled
            New-User 'u3@contoso.com' $true $script:Old @($script:E3)                 # tier3: inactive
            New-User 'u4@contoso.com' $true $script:Recent @($script:E3, $script:ExP1) # tier5: overlap
            New-User 'guest@ext.com' $true $script:Recent @($script:E5) 'Guest'        # excluded
            New-User 'room@contoso.com' $true $script:Recent @($script:E5) 'Member' $true # excluded (resource)
        )
        # u1 mailbox-only; u4 uses collaboration too (so not a downgrade candidate)
        $script:Activity = @(
            [pscustomobject]@{ userPrincipalName = 'u1@contoso.com'; exchangeLastActivityDate = $script:Recent; oneDriveLastActivityDate = ''; sharePointLastActivityDate = ''; teamsLastActivityDate = ''; yammerLastActivityDate = '' }
            [pscustomobject]@{ userPrincipalName = 'u4@contoso.com'; exchangeLastActivityDate = $script:Recent; oneDriveLastActivityDate = $script:Recent; sharePointLastActivityDate = ''; teamsLastActivityDate = $script:Recent; yammerLastActivityDate = '' }
        )
    }

    It 'computes the monthly spend from assigned seats x price' {
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity
        # 8*38 + 5*23 + 2*4 = 427
        $Report.Summary.MonthlySpend | Should -Be 427.0
        $Report.Summary.PriceCoverage | Should -Be 1
    }

    It 'flags unassigned seats (tier 1) with per-seat pricing' {
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity
        $Opp = $Report.Opportunities | Where-Object { $_.Tier -eq 'UnassignedSeats' -and $_.skuId -eq $script:E5 }
        $Opp.Seats | Should -Be 2
        $Opp.MonthlySaving | Should -Be 76.0
    }

    It 'flags a disabled account (tier 2)' {
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity
        $Opp = $Report.Opportunities | Where-Object { $_.Tier -eq 'DisabledAccount' }
        $Opp.Seats | Should -Be 1
        $Opp.MonthlySaving | Should -Be 38.0
        $Opp.Users | Should -Contain 'u2@contoso.com'
    }

    It 'flags an inactive account (tier 3)' {
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity
        $Opp = $Report.Opportunities | Where-Object { $_.Tier -eq 'Inactive' }
        $Opp.Seats | Should -Be 1
        $Opp.MonthlySaving | Should -Be 23.0
        $Opp.Users | Should -Contain 'u3@contoso.com'
    }

    It 'flags a mailbox-only premium user for review (tier 4) without claiming a saving' {
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity
        $Opp = $Report.Opportunities | Where-Object { $_.Tier -eq 'Downgrade' }
        $Opp.Seats | Should -Be 1
        # Review only: no monetary saving is claimed, but the SKU itself is priced (E5).
        $Opp.MonthlySaving | Should -Be 0
        $Opp.UnitCost | Should -Be 38.0
        $Opp.PriceKnown | Should -BeTrue
        $Opp.Users | Should -Contain 'u1@contoso.com'
    }

    It 'flags a redundant overlapping SKU (tier 5)' {
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity
        $Opp = $Report.Opportunities | Where-Object { $_.Tier -eq 'Overlap' }
        $Opp.skuId | Should -Be $script:ExP1
        $Opp.Seats | Should -Be 1
        $Opp.MonthlySaving | Should -Be 4.0
    }

    It 'totals reclaimable spend and reclaimable seats' {
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity
        # 76 (t1 E5) + 4 (t1 ExP1) + 38 (t2) + 23 (t3) + 0 (t4 review) + 4 (t5) = 145
        $Report.Summary.ReclaimableMonthly | Should -Be 145.0
        # tiers 1-3 seats only: (2+1) + 1 + 1 = 5
        $Report.Summary.ReclaimableSeats | Should -Be 5
        $Report.Summary.AnonymizedReports | Should -BeFalse
    }

    It 'excludes guests and resource accounts from per-user tiers' {
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity
        $AllUsers = @($Report.Opportunities.Users)
        $AllUsers | Should -Not -Contain 'guest@ext.com'
        $AllUsers | Should -Not -Contain 'room@contoso.com'
    }

    It 'marks unpriced SKUs as PriceKnown false with zero saving' {
        $NoPriceLic = @(New-Lic '00000000-0000-0000-0000-000000000000' 'Mystery SKU' 4 2 @('X'))
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $NoPriceLic -Users @() -ActivityDetail @()
        $Opp = $Report.Opportunities | Where-Object { $_.Tier -eq 'UnassignedSeats' }
        $Opp.PriceKnown | Should -BeFalse
        $Opp.UnitCost | Should -BeNullOrEmpty
        $Opp.MonthlySaving | Should -Be 0
        $Opp.Seats | Should -Be 2
    }

    It 'detects anonymized usage reports when activity UPNs do not match users' {
        $AnonActivity = @(
            [pscustomobject]@{ userPrincipalName = 'AB6E27EA1F9A4C00'; exchangeLastActivityDate = $script:Recent; oneDriveLastActivityDate = ''; sharePointLastActivityDate = ''; teamsLastActivityDate = ''; yammerLastActivityDate = '' }
        )
        $Report = Get-CIPPLicenseOptimization -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $AnonActivity
        $Report.Summary.AnonymizedReports | Should -BeTrue
    }
}

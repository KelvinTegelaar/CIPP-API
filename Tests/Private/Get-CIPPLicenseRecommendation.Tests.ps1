# Pester tests for Get-CIPPLicenseRecommendation — downgrade targets from usage evidence,
# consolidation / protection upgrades, and the annual-vs-monthly term split.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPLicenseRecommendation.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPLicenseRecommendation.ps1 under Modules/' }

    function Get-CIPPLicensePrice { param($SkuId, $Currency, [switch]$ListCurrencies) }
    function Get-CIPPLicenseCatalog { param([switch]$Force) }
    function Get-CIPPLicenseOptimization { param($TenantFilter, $Licenses, $Users, $ActivityDetail, $InactiveDays, $Currency) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function New-GraphGetRequest { param($uri, $tenantid, [switch]$ComplexFilter) }
    function Get-CIPPLicenseOverview { param($TenantFilter) }

    . $FunctionPath

    # SKUs
    $script:Basic = '3b555118-da6a-4418-894f-7df1e2096870'
    $script:Standard = 'f245ecc8-75af-4f8e-b61f-27d8114de5f3'
    $script:Premium = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46'
    $script:AppsBiz = 'cdd28e44-67e3-425e-be4c-737fab2899d3'
    $script:ExP1 = '4b9405b0-7788-4568-add1-99614e613b69'
    $script:Copilot = '639dec6b-bb19-468b-871c-c5c441c4b0cb'

    # Service plans
    $script:PlanExchange = '9aaf7827-d63c-4b61-89c3-182f06f82e5c'
    $script:PlanTeams = '57ff2da0-773e-42df-b2af-ffb7a2317929'
    $script:PlanSpo = 'c7699d2e-19aa-44de-8edf-1736da088ca1'
    $script:PlanOfficeBiz = '094e7854-93fc-4d55-b2c0-3ab5369ebdc1'
    $script:PlanIntune = 'c1ec4a95-1f05-45b3-a911-aa3fa01094f5'
    $script:PlanAadP1 = '41781fb2-bc02-4b7c-bd55-b576c07bb09d'
    $script:PlanMde = 'bfc1bbd9-981b-4f71-9b82-17c35fd0e2a4'
    $script:PlanCopilot = 'a62f8878-de10-42f3-b68f-6149a25ceb97'

    $script:PlanIds = @{
        $script:Basic    = @($script:PlanExchange, $script:PlanTeams, $script:PlanSpo)
        $script:Standard = @($script:PlanExchange, $script:PlanTeams, $script:PlanSpo, $script:PlanOfficeBiz)
        $script:Premium  = @($script:PlanExchange, $script:PlanTeams, $script:PlanSpo, $script:PlanOfficeBiz, $script:PlanIntune, $script:PlanAadP1, $script:PlanMde)
        $script:AppsBiz  = @($script:PlanOfficeBiz)
        $script:ExP1     = @($script:PlanExchange)
        $script:Copilot  = @($script:PlanCopilot)
    }

    function New-Lic { param($SkuId, $Name, $Total, $Used, $Terms = @())
        [pscustomobject]@{ skuId = $SkuId; License = $Name; TotalLicenses = "$Total"; CountUsed = "$Used"; ServicePlans = @(); TermInfo = @($Terms) }
    }
    function New-User { param($Upn, $Skus, $AssignedSince, $Created = (Get-Date).AddYears(-2).ToString('o'), $Enabled = $true)
        [pscustomobject]@{
            userPrincipalName       = $Upn
            displayName             = $Upn
            accountEnabled          = $Enabled
            userType                = 'Member'
            isResourceAccount       = $false
            createdDateTime         = $Created
            signInActivity          = [pscustomobject]@{ lastSignInDateTime = (Get-Date).AddDays(-2).ToString('o'); lastNonInteractiveSignInDateTime = $null }
            assignedLicenses        = @($Skus | ForEach-Object { [pscustomobject]@{ skuId = $_; disabledPlans = @() } })
            licenseAssignmentStates = @($Skus | ForEach-Object { [pscustomobject]@{ skuId = $_; state = 'Active'; lastUpdatedDateTime = $AssignedSince } })
        }
    }
    function New-Activity { param($Upn, $Exchange, $Teams, $Files)
        $Recent = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd')
        [pscustomobject]@{
            userPrincipalName          = $Upn
            exchangeLastActivityDate   = if ($Exchange) { $Recent } else { '' }
            teamsLastActivityDate      = if ($Teams) { $Recent } else { '' }
            oneDriveLastActivityDate   = if ($Files) { $Recent } else { '' }
            sharePointLastActivityDate = ''
            yammerLastActivityDate     = ''
        }
    }
    function New-AppUsage { param($Upn, $Windows)
        [pscustomobject]@{ userPrincipalName = $Upn; details = @([pscustomobject]@{ reportPeriod = 180; windows = $Windows; mac = $false; web = $true; mobile = $false }) }
    }
}

Describe 'Get-CIPPLicenseRecommendation' {
    BeforeEach {
        Mock -CommandName Get-CIPPLicenseCatalog -MockWith {
            [pscustomobject]@{
                meta         = [pscustomobject]@{ monthlyCommitmentUplift = 0.2; seatLimits = [pscustomobject]@{ business = 300 } }
                capabilities = @(
                    [pscustomobject]@{ id = 'email'; label = 'Email and calendar'; signal = 'exchange'; servicePlanIds = @($script:PlanExchange) }
                    [pscustomobject]@{ id = 'teams'; label = 'Teams chat and meetings'; signal = 'teams'; servicePlanIds = @($script:PlanTeams) }
                    [pscustomobject]@{ id = 'files'; label = 'File storage and sharing'; signal = 'files'; servicePlanIds = @($script:PlanSpo) }
                    [pscustomobject]@{ id = 'desktopApps'; label = 'Office desktop apps'; signal = 'desktopApps'; servicePlanIds = @($script:PlanOfficeBiz) }
                    [pscustomobject]@{ id = 'copilot'; label = 'Microsoft 365 Copilot'; signal = 'copilot'; servicePlanIds = @($script:PlanCopilot) }
                    [pscustomobject]@{ id = 'deviceManagement'; label = 'Device management'; signal = $null; servicePlanIds = @($script:PlanIntune) }
                    [pscustomobject]@{ id = 'signInSecurity'; label = 'Advanced sign-in security'; signal = $null; servicePlanIds = @($script:PlanAadP1) }
                    [pscustomobject]@{ id = 'endpointSecurity'; label = 'Device threat protection'; signal = $null; servicePlanIds = @($script:PlanMde) }
                )
                families     = @()
                products     = @(
                    [pscustomobject]@{ skuId = $script:Basic; skuPartNumber = 'O365_BUSINESS_ESSENTIALS'; name = 'Business Basic'; family = 'business'; tier = 1; eligibleTarget = $true }
                    [pscustomobject]@{ skuId = $script:Standard; skuPartNumber = 'O365_BUSINESS_PREMIUM'; name = 'Business Standard'; family = 'business'; tier = 2; eligibleTarget = $true }
                    [pscustomobject]@{ skuId = $script:Premium; skuPartNumber = 'SPB'; name = 'Business Premium'; family = 'business'; tier = 3; eligibleTarget = $true }
                    [pscustomobject]@{ skuId = $script:AppsBiz; skuPartNumber = 'O365_BUSINESS'; name = 'Apps for Business'; family = 'apps'; tier = 1; eligibleTarget = $true }
                    [pscustomobject]@{ skuId = $script:ExP1; skuPartNumber = 'EXCHANGESTANDARD'; name = 'Exchange P1'; family = 'exchange'; tier = 1; eligibleTarget = $true }
                    [pscustomobject]@{ skuId = $script:Copilot; skuPartNumber = 'Microsoft_365_Copilot'; name = 'Copilot'; family = 'addon'; tier = 0; eligibleTarget = $false }
                )
            }
        }
        Mock -CommandName Get-CIPPLicensePrice -MockWith {
            @(
                [pscustomobject]@{ skuId = $script:Basic; Product_Display_Name = 'Business Basic'; MonthlyPrice = 7.0; Currency = 'USD'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:Standard; Product_Display_Name = 'Business Standard'; MonthlyPrice = 14.0; Currency = 'USD'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:Premium; Product_Display_Name = 'Business Premium'; MonthlyPrice = 22.0; Currency = 'USD'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:AppsBiz; Product_Display_Name = 'Apps for Business'; MonthlyPrice = 10.0; Currency = 'USD'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:ExP1; Product_Display_Name = 'Exchange P1'; MonthlyPrice = 4.0; Currency = 'USD'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:Copilot; Product_Display_Name = 'Copilot'; MonthlyPrice = 30.0; Currency = 'USD'; Source = 'Estimate' }
            )
        }
        Mock -CommandName Get-CIPPLicenseOptimization -MockWith {
            [pscustomobject]@{
                Summary       = [pscustomobject]@{ MonthlySpend = 100.0; ReclaimableMonthly = 10.0; ReclaimableSeats = 1; AssignedSeats = 5; PriceCoverage = 1; AnonymizedReports = $false; DataAvailable = $true }
                # The reclaimable money is recounted from the findings, so the summary and the list agree
                Opportunities = @(
                    [pscustomobject]@{ Tier = 'UnassignedSeats'; FindingLabel = 'Unassigned'; License = 'Apps for Business'; skuId = $script:AppsBiz; Seats = 1; UnitCost = 10.0; MonthlySaving = 10.0; SuggestedAction = 'Reduce seat count'; Users = @(); PriceKnown = $true }
                )
            }
        }

        $script:Old = (Get-Date).AddMonths(-9).ToString('o')
        $script:New = (Get-Date).AddMonths(-1).ToString('o')
        $script:Licenses = @(
            New-Lic $script:Standard 'Business Standard' 10 4 @(
                [pscustomobject]@{ Status = 'Enabled'; Term = 'Monthly'; TotalLicenses = 6; DaysUntilRenew = 12 }
                [pscustomobject]@{ Status = 'Enabled'; Term = 'Yearly'; TotalLicenses = 4; DaysUntilRenew = 200 }
            )
            New-Lic $script:Premium 'Business Premium' 2 1
            New-Lic $script:Basic 'Business Basic' 2 1
            New-Lic $script:AppsBiz 'Apps for Business' 2 1
            New-Lic $script:Copilot 'Copilot' 1 1
        )
        $script:Users = @(
            # Standard, never opens the desktop apps -> Basic
            New-User 'mailonly@contoso.com' @($script:Standard) $script:Old
            # Standard, uses desktop apps -> stays
            New-User 'power@contoso.com' @($script:Standard) $script:Old
            # Standard, new hire (1 month), uses apps -> stays, but not stable for annual
            New-User 'newhire@contoso.com' @($script:Standard) $script:New
            # Standard, no usage data at all -> no claim
            New-User 'unknown@contoso.com' @($script:Standard) $script:Old
            # Premium, only email -> protected security features keep it on Premium
            New-User 'premium@contoso.com' @($script:Premium) $script:Old
            # Basic + Apps for Business (17) -> consolidate into Standard (14)
            New-User 'combo@contoso.com' @($script:Basic, $script:AppsBiz) $script:Old
            # Copilot never used -> remove
            New-User 'copilot@contoso.com' @($script:Copilot, $script:Premium) $script:Old
        )
        $script:Activity = @(
            New-Activity 'mailonly@contoso.com' $true $false $false
            New-Activity 'power@contoso.com' $true $true $true
            New-Activity 'newhire@contoso.com' $true $true $true
            New-Activity 'premium@contoso.com' $true $false $false
            New-Activity 'combo@contoso.com' $true $true $true
            New-Activity 'copilot@contoso.com' $true $true $true
        )
        $script:Apps = @(
            New-AppUsage 'mailonly@contoso.com' $false
            New-AppUsage 'power@contoso.com' $true
            New-AppUsage 'newhire@contoso.com' $true
            New-AppUsage 'premium@contoso.com' $false
            New-AppUsage 'combo@contoso.com' $true
            New-AppUsage 'copilot@contoso.com' $true
        )
    }

    It 'recommends the cheapest plan with a mailbox for a Standard user who only uses email' {
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        # Only email is in evidence, so Exchange P1 (4) beats Business Basic (7)
        $Row = $Report.Downgrades | Where-Object { $_.FromSkuId -eq $script:Standard -and $_.ToSkuId -eq $script:ExP1 }
        $Row | Should -Not -BeNullOrEmpty
        $Row.Seats | Should -Be 1
        $Row.Users.userPrincipalName | Should -Be 'mailonly@contoso.com'
        $Row.UnitSaving | Should -Be 10.0
        $Row.Loses | Should -Contain 'Office desktop apps'
        $Row.Loses | Should -Contain 'Teams chat and meetings'
        $Row.Keeps | Should -Contain 'Email and calendar'
    }

    It 'makes no claim about a user with no usage data and keeps a desktop-app user on Standard' {
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Upns = @($Report.Downgrades | ForEach-Object { $_.Users.userPrincipalName })
        $Upns | Should -Not -Contain 'unknown@contoso.com'
        $Upns | Should -Not -Contain 'power@contoso.com'
    }

    It 'keeps a Premium user on Premium while security features are protected, and downgrades when they are not' {
        $Protected = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds
        @($Protected.Downgrades | Where-Object { $_.FromSkuId -eq $script:Premium }) | Should -BeNullOrEmpty

        $Open = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -ProtectSecurityFeatures $false -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds
        $Row = $Open.Downgrades | Where-Object { $_.FromSkuId -eq $script:Premium -and $_.Users.userPrincipalName -contains 'premium@contoso.com' }
        $Row | Should -Not -BeNullOrEmpty
        # Only email is in evidence, so the cheapest plan with a mailbox wins
        $Row.ToSkuId | Should -Be $script:ExP1
        $Row.Loses | Should -Contain 'Device management'
    }

    It 'recommends removing an unused Copilot add-on' {
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Row = $Report.Downgrades | Where-Object { $_.FromSkuId -eq $script:Copilot }
        $Row | Should -Not -BeNullOrEmpty
        $Row.Action | Should -Be 'Remove'
        $Row.UnitSaving | Should -Be 30.0
    }

    It 'consolidates Basic + Apps for Business into Standard' {
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Row = $Report.Upgrades | Where-Object { $_.Type -eq 'Consolidate' -and $_.ToSkuId -eq $script:Standard }
        $Row | Should -Not -BeNullOrEmpty
        $Row.UnitCost | Should -Be 17.0
        $Row.UnitDelta | Should -Be (-3.0)
        $Row.Users.userPrincipalName | Should -Be 'combo@contoso.com'
        $Report.Summary.ConsolidationMonthly | Should -Be 3.0
    }

    It 'flags unprotected users with the cheapest plan that adds security, as an investment' {
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Rows = @($Report.Upgrades | Where-Object { $_.Type -eq 'Protect' })
        $Rows.Count | Should -BeGreaterThan 0
        ($Rows | ForEach-Object { $_.ToSkuId } | Select-Object -Unique) | Should -Be $script:Premium
        $Report.Summary.ProtectInvestmentMonthly | Should -BeGreaterThan 0
        # Premium holders are never in the protect list
        @($Rows | ForEach-Object { $_.Users.userPrincipalName }) | Should -Not -Contain 'premium@contoso.com'
    }

    It 'recommends the annual/monthly split from assignment tenure and values the convertible seats' {
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -TenureMonths 6 -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Row = $Report.Terms | Where-Object { $_.skuId -eq $script:Standard }
        $Row | Should -Not -BeNullOrEmpty
        $Row.AssignedSeats | Should -Be 4
        # mailonly, power, unknown are 9 months in; newhire is 1 month in
        $Row.StableSeats | Should -Be 3
        $Row.RecommendedAnnual | Should -Be 3
        $Row.RecommendedMonthly | Should -Be 1
        $Row.MonthlySeats | Should -Be 6
        $Row.YearlySeats | Should -Be 4
        # 4 seats already annual cover the 3 stable ones: nothing left to convert
        $Row.ConvertibleSeats | Should -Be 0
        # 4 annual seats but only 4 assigned -> nothing locked and unused
        $Row.LockedUnusedSeats | Should -Be 0
        $Row.NextRenewalDays | Should -Be 12
    }

    It 'values monthly seats that should move to annual at the commitment uplift' {
        $Licenses = @(New-Lic $script:Standard 'Business Standard' 4 4 @([pscustomobject]@{ Status = 'Enabled'; Term = 'Monthly'; TotalLicenses = 4; DaysUntilRenew = 12 }))
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Row = $Report.Terms | Where-Object { $_.skuId -eq $script:Standard }
        $Row.ConvertibleSeats | Should -Be 3
        # 3 seats x 14 x 20%
        $Row.MonthlySaving | Should -Be 8.4
        $Report.Summary.TermMonthly | Should -Be 8.4
    }

    It 'skips each analysis when its switch is off' {
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -RecommendDowngrades $false -RecommendUpgrades $false -RecommendTerms $false -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        @($Report.Downgrades).Count | Should -Be 0
        @($Report.Upgrades).Count | Should -Be 0
        @($Report.Terms).Count | Should -Be 0
        $Report.Summary.TotalPotentialMonthly | Should -Be 10.0
    }

    It 'makes no downgrade claims when usage reports are anonymized' {
        $Anon = @(New-Activity 'AB6E27EA1F9A4C00' $true $false $false)
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $Anon -AppUsage @() -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Report.Summary.AnonymizedReports | Should -BeTrue
        @($Report.Downgrades).Count | Should -Be 0
    }

    It 'flattens every finding into one suggestion list with a user, an action and a reason' {
        Mock -CommandName Get-CIPPLicenseOptimization -MockWith {
            [pscustomobject]@{
                Summary       = [pscustomobject]@{ MonthlySpend = 100.0; ReclaimableMonthly = 21.0; ReclaimableSeats = 2; AssignedSeats = 5; PriceCoverage = 1; AnonymizedReports = $false; DataAvailable = $true }
                Opportunities = @(
                    [pscustomobject]@{ Tier = 'UnassignedSeats'; FindingLabel = 'Unassigned'; License = 'Business Standard'; skuId = $script:Standard; Seats = 6; UnitCost = 14.0; MonthlySaving = 84.0; SuggestedAction = 'Reduce seat count'; Users = @(); PriceKnown = $true }
                    [pscustomobject]@{ Tier = 'Inactive'; FindingLabel = 'Inactive 90d+'; License = 'Business Basic'; skuId = $script:Basic; Seats = 1; UnitCost = 7.0; MonthlySaving = 7.0; SuggestedAction = 'Review / remove'; Users = @('power@contoso.com'); PriceKnown = $true }
                )
            }
        }
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Rows = @($Report.Suggestions)
        $Rows.Count | Should -Be $Report.Summary.SuggestionCount
        ($Rows | Where-Object { $_.Type -eq 'Reduce seats' }).Suggestion | Should -Be 'Reduce the seat count by 6'
        $Inactive = $Rows | Where-Object { $_.Type -eq 'Remove license' -and $_.User -eq 'power@contoso.com' -and $_.skuId -eq $script:Basic }
        $Inactive.Reason | Should -Match 'No sign-in for \d+ days'
        $Inactive.MonthlySaving | Should -Be 7.0
        $Change = $Rows | Where-Object { $_.Type -eq 'Change license' -and $_.User -eq 'mailonly@contoso.com' }
        $Change.TargetLicense | Should -Be 'Exchange P1'
        $Change.Reason | Should -Match 'Used only Email and calendar'
        ($Rows | Where-Object { $_.Type -eq 'Combine licenses' }).User | Should -Be 'combo@contoso.com'
        ($Rows | Where-Object { $_.Type -eq 'Add protection' }).MonthlySaving | ForEach-Object { $_ | Should -BeLessThan 0 }
        # Sorted by saving, biggest first
        $Rows[0].MonthlySaving | Should -Be 84.0
    }

    It 'falls back to usage-report activity when the tenant has no sign-in data (no Entra ID P1)' {
        # Strip sign-in data from everyone; "unknown" has no activity row, "mailonly" has activity
        $Users = @($script:Users | ForEach-Object { $_.signInActivity = $null; $_ })
        $Idle = New-User 'idle@contoso.com' @($script:Standard) $script:Old
        $Idle.signInActivity = $null
        $Users = @($Users) + $Idle
        $Activity = @($script:Activity) + (New-Activity 'idle@contoso.com' $false $false $false)

        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $Users -ActivityDetail $Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Report.Summary.SignInDataAvailable | Should -BeFalse
        $Row = $Report.Suggestions | Where-Object { $_.User -eq 'idle@contoso.com' }
        $Row.Type | Should -Be 'Remove license'
        $Row.Reason | Should -Match 'No activity in email, Teams, OneDrive or SharePoint'
        $Row.MonthlySaving | Should -Be 14.0
        # A user with activity keeps getting plan recommendations; one with no report row is left alone
        @($Report.Suggestions | Where-Object { $_.User -eq 'mailonly@contoso.com' -and $_.Type -eq 'Change license' }).Count | Should -Be 1
        @($Report.Suggestions | Where-Object { $_.User -eq 'unknown@contoso.com' -and $_.Type -eq 'Remove license' }).Count | Should -Be 0
        $Report.Summary.ReclaimableMonthly | Should -Be 24.0
    }

    It 'never reports unassigned seats of tenant-level SKUs (storage, server protection) as waste' {
        $Storage = '99049c9c-6011-4908-bf17-15f496e6519d'
        Mock -CommandName Get-CIPPLicenseCatalog -MockWith {
            [pscustomobject]@{
                meta         = [pscustomobject]@{ monthlyCommitmentUplift = 0.2; seatLimits = [pscustomobject]@{ business = 300 }; tenantLevelSkus = @($Storage) }
                capabilities = @()
                families     = @()
                products     = @([pscustomobject]@{ skuId = $script:Standard; family = 'business'; tier = 2; eligibleTarget = $true })
            }
        }
        Mock -CommandName Get-CIPPLicenseOptimization -MockWith {
            [pscustomobject]@{
                Summary       = [pscustomobject]@{ MonthlySpend = 100.0; ReclaimableMonthly = 100.0; ReclaimableSeats = 7; AssignedSeats = 5; PriceCoverage = 1; AnonymizedReports = $false; DataAvailable = $true }
                Opportunities = @(
                    [pscustomobject]@{ Tier = 'UnassignedSeats'; FindingLabel = 'Unassigned'; License = 'Office 365 Extra File Storage'; skuId = $Storage; Seats = 5; UnitCost = 0.2; MonthlySaving = 1.0; SuggestedAction = 'Reduce seat count'; Users = @(); PriceKnown = $true }
                    [pscustomobject]@{ Tier = 'UnassignedSeats'; FindingLabel = 'Unassigned'; License = 'Business Standard'; skuId = $script:Standard; Seats = 2; UnitCost = 14.0; MonthlySaving = 28.0; SuggestedAction = 'Reduce seat count'; Users = @(); PriceKnown = $true }
                )
            }
        }
        $Licenses = @($script:Licenses) + (New-Lic $Storage 'Office 365 Extra File Storage' 500 0)

        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -RecommendDowngrades $false -RecommendUpgrades $false -Licenses $Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        @($Report.Suggestions | Where-Object { $_.skuId -eq $Storage }).Count | Should -Be 0
        @($Report.Suggestions | Where-Object { $_.Type -eq 'Reduce seats' }).Count | Should -Be 1
        $Report.Summary.ReclaimableMonthly | Should -Be 28.0
        $Report.Summary.ReclaimableSeats | Should -Be 2
        ($Report.Products | Where-Object { $_.skuId -eq $Storage }).UnusedSeats | Should -Be 0
        ($Report.Products | Where-Object { $_.skuId -eq $Storage }).TenantLevel | Should -BeTrue
        @($Report.Terms | Where-Object { $_.skuId -eq $Storage }).Count | Should -Be 0
    }

    It 'sums the potential into the summary and lists what is paid for' {
        $Report = Get-CIPPLicenseRecommendation -TenantFilter 'contoso.com' -Licenses $script:Licenses -Users $script:Users -ActivityDetail $script:Activity -AppUsage $script:Apps -MailboxUsage @() -CopilotUsage @() -PlanIdsBySku $script:PlanIds

        $Report.Summary.TotalPotentialMonthly | Should -Be ([math]::Round(10.0 + $Report.Summary.DowngradeMonthly + $Report.Summary.ConsolidationMonthly + $Report.Summary.TermMonthly, 2))
        $Report.Summary.TotalPotentialAnnual | Should -Be ([math]::Round($Report.Summary.TotalPotentialMonthly * 12, 2))
        $Report.Summary.ReportPeriodDays | Should -Be 180
        @($Report.Products).Count | Should -Be 5
        ($Report.Products | Where-Object { $_.skuId -eq $script:Premium }).Capabilities | Should -Contain 'Device management'
        ($Report.Products | Where-Object { $_.skuId -eq $script:Standard }).MonthlySpend | Should -Be 56.0
    }
}

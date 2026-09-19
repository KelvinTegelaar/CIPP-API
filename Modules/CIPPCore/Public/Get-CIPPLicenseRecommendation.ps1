function Get-CIPPLicenseRecommendation {
    <#
    .SYNOPSIS
        Build the full license recommendation report for a tenant.

    .DESCRIPTION
        Extends Get-CIPPLicenseOptimization (unassigned / disabled / inactive / overlapping seats)
        with three evidence-based recommendation sets, all priced through Get-CIPPLicensePrice:

        Downgrades  - for every active licensed user, the capabilities of each plan they hold are
                      split into measurable ones (email, Teams, files, desktop apps, large mailbox,
                      Copilot - each backed by a Microsoft usage report) and unmeasurable ones
                      (Intune, Entra P1/P2, Defender, Purview, ...). The cheapest catalog plan that
                      still covers every capability the user actually used - and, when
                      -ProtectSecurityFeatures is on, every unmeasurable capability of the current
                      plan - is the recommended target. No cheaper plan means no recommendation.
                      A plan whose measurable capabilities are all unused and that carries nothing
                      unmeasurable (a Copilot add-on nobody opens) is recommended for removal.
        Upgrades    - 'Consolidate': a user holding several plans whose combined capabilities a
                      single cheaper plan covers. 'Protect': users whose plans include no device
                      management, sign-in security or device threat protection, with the cheapest
                      plan that adds all three (an investment, reported separately from savings).
        Terms       - per owned SKU, how many assigned seats have been held for at least
                      -TenureMonths (licenseAssignmentStates.lastUpdatedDateTime is the floor of
                      the assignment age), the current monthly/annual split from the tenant's
                      subscriptions, and the recommended split. Seats on a monthly term that are
                      stable enough to commit annually are valued at the catalog's monthly-commitment
                      uplift (20%).

        Every input defaults to the reporting-DB cache. License overview and the two usage reports
        fall back to a live Graph read when the cache is empty, so the report works on a tenant the
        nightly collection has not reached yet.

    .PARAMETER TenantFilter
        The tenant (domain or GUID) to report on.

    .PARAMETER Currency
        ISO currency code the money figures are resolved in. Default USD.

    .PARAMETER RecommendDowngrades
        Include the downgrade analysis. Default $true.

    .PARAMETER RecommendUpgrades
        Include the consolidation and protection analysis. Default $true.

    .PARAMETER RecommendTerms
        Include the annual/monthly commitment analysis. Default $true.

    .PARAMETER ProtectSecurityFeatures
        When $true (default) a downgrade target must keep every security, compliance, identity and
        device-management capability of the current plan, since usage reports cannot show whether
        those are relied on. When $false only the capabilities the user measurably used must be kept
        and the report lists what would be lost.

    .PARAMETER TenureMonths
        Months a seat must have been assigned to count as stable for an annual commitment. Default 6.

    .PARAMETER InactiveDays
        Sign-in / activity age in days past which a user counts as inactive. Default 90.

    .PARAMETER Licenses
        Optional. LicenseOverview records (Get-CIPPLicenseOverview shape).

    .PARAMETER Users
        Optional. User records with assignedLicenses, licenseAssignmentStates and signInActivity.

    .PARAMETER ActivityDetail
        Optional. getOffice365ActiveUserDetail rows.

    .PARAMETER AppUsage
        Optional. getM365AppUserDetail rows.

    .PARAMETER MailboxUsage
        Optional. getMailboxUsageDetail rows.

    .PARAMETER CopilotUsage
        Optional. getMicrosoft365CopilotUsageUserDetail rows.

    .PARAMETER PlanIdsBySku
        Optional. Hashtable of skuId (lower) -> string[] service plan ids. Defaults to ConversionTable.csv.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$Currency = 'USD',
        [bool]$RecommendDowngrades = $true,
        [bool]$RecommendUpgrades = $true,
        [bool]$RecommendTerms = $true,
        [bool]$ProtectSecurityFeatures = $true,
        [int]$TenureMonths = 6,
        [int]$InactiveDays = 90,
        $Licenses,
        $Users,
        $ActivityDetail,
        $AppUsage,
        $MailboxUsage,
        $CopilotUsage,
        [hashtable]$PlanIdsBySku
    )

    if ($TenureMonths -le 0) { $TenureMonths = 6 }
    if ($InactiveDays -le 0) { $InactiveDays = 90 }
    $Now = Get-Date
    $Cutoff = $Now.AddDays(-$InactiveDays)
    $Sources = [ordered]@{}

    # ------------------------------------------------------------------ inputs (cache, then live)
    if (-not $PSBoundParameters.ContainsKey('Licenses')) {
        $Licenses = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'LicenseOverview')
        $Sources.Licenses = 'Cache'
        if ($Licenses.Count -eq 0) {
            try { $Licenses = @(Get-CIPPLicenseOverview -TenantFilter $TenantFilter); $Sources.Licenses = 'Live' } catch { Write-Information "License overview live fallback failed: $($_.Exception.Message)" }
        }
    }
    if (-not $PSBoundParameters.ContainsKey('Users')) {
        $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users')
        $Sources.Users = 'Cache'
        if ($Users.Count -eq 0) {
            $Select = 'id,userPrincipalName,displayName,accountEnabled,userType,createdDateTime,assignedLicenses,licenseAssignmentStates,isResourceAccount'
            try {
                $Users = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=500&`$select=$Select,signInActivity&`$count=true" -ComplexFilter -tenantid $TenantFilter)
                $Sources.Users = 'Live'
            } catch {
                try { $Users = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=$Select" -tenantid $TenantFilter); $Sources.Users = 'Live' } catch { Write-Information "Users live fallback failed: $($_.Exception.Message)" }
            }
        }
    }
    if (-not $PSBoundParameters.ContainsKey('ActivityDetail')) {
        $ActivityDetail = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ActiveUserDetail')
        $Sources.ActivityDetail = 'Cache'
        if ($ActivityDetail.Count -eq 0) {
            try { $ActivityDetail = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getOffice365ActiveUserDetail(period='D90')?`$format=application%2fjson" -tenantid $TenantFilter); $Sources.ActivityDetail = 'Live' } catch { Write-Information "Active user detail live fallback failed: $($_.Exception.Message)" }
        }
    }
    if (-not $PSBoundParameters.ContainsKey('AppUsage')) {
        $AppUsage = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'M365AppUserDetail')
        $Sources.AppUsage = 'Cache'
        if ($AppUsage.Count -eq 0) {
            try { $AppUsage = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getM365AppUserDetail(period='D90')?`$format=application%2fjson" -tenantid $TenantFilter); $Sources.AppUsage = 'Live' } catch { Write-Information "App usage live fallback failed: $($_.Exception.Message)" }
        }
    }
    if (-not $PSBoundParameters.ContainsKey('MailboxUsage')) { $MailboxUsage = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'MailboxUsage'); $Sources.MailboxUsage = 'Cache' }
    if (-not $PSBoundParameters.ContainsKey('CopilotUsage')) { $CopilotUsage = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'CopilotUsageUserDetail'); $Sources.CopilotUsage = 'Cache' }

    $Licenses = @($Licenses)
    $Users = @($Users)
    $ActivityDetail = @($ActivityDetail)
    $AppUsage = @($AppUsage)
    $MailboxUsage = @($MailboxUsage)
    $CopilotUsage = @($CopilotUsage)

    $Catalog = Get-CIPPLicenseCatalog
    $Uplift = if ($Catalog.meta.monthlyCommitmentUplift) { [double]$Catalog.meta.monthlyCommitmentUplift } else { 0.20 }

    # ------------------------------------------------------------------ service plans per SKU
    if (-not $PlanIdsBySku) {
        $PlanIdsBySku = @{}
        try {
            $TablePath = Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv'
            if (Test-Path $TablePath) {
                foreach ($Row in ([System.IO.File]::ReadAllText($TablePath) | ConvertFrom-Csv)) {
                    $Key = ([string]$Row.GUID).ToLowerInvariant()
                    if (-not $Key -or -not $Row.Service_Plan_Id) { continue }
                    if (-not $PlanIdsBySku.ContainsKey($Key)) { $PlanIdsBySku[$Key] = [System.Collections.Generic.List[string]]::new() }
                    $PlanIdsBySku[$Key].Add(([string]$Row.Service_Plan_Id).ToLowerInvariant())
                }
            }
        } catch { Write-Information "ConversionTable read failed: $($_.Exception.Message)" }
    }
    $PlanSetOf = @{}
    $GetPlanSet = {
        param($Sku)
        $Key = ([string]$Sku).ToLowerInvariant()
        if ($PlanSetOf.ContainsKey($Key)) { return , $PlanSetOf[$Key] }
        $Set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($PlanIdsBySku.ContainsKey($Key)) { foreach ($Id in @($PlanIdsBySku[$Key])) { $null = $Set.Add([string]$Id) } }
        $PlanSetOf[$Key] = $Set
        return , $Set
    }
    # The tenant's own subscribedSkus service plans top up the table (new plans land there first)
    foreach ($Lic in $Licenses) {
        if (-not $Lic.skuId) { continue }
        $Set = & $GetPlanSet $Lic.skuId
        foreach ($Plan in @($Lic.ServicePlans)) { if ($Plan.servicePlanId) { $null = $Set.Add(([string]$Plan.servicePlanId).ToLowerInvariant()) } }
    }

    # ------------------------------------------------------------------ capabilities
    $Capabilities = @($Catalog.capabilities)
    $CapById = @{}
    foreach ($Cap in $Capabilities) { $CapById[[string]$Cap.id] = $Cap }
    # cap id -> which capability ids a plan set includes (respecting per-user disabled plans)
    $CapsOfPlans = {
        param($PlanSet, $Disabled)
        $Result = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Cap in $Capabilities) {
            foreach ($Id in @($Cap.servicePlanIds)) {
                $Id = ([string]$Id).ToLowerInvariant()
                if ($PlanSet.Contains($Id) -and -not ($Disabled -and $Disabled.Contains($Id))) { $null = $Result.Add([string]$Cap.id); break }
            }
        }
        return , $Result
    }
    $CapLabel = { param($Id) if ($CapById.ContainsKey($Id)) { [string]$CapById[$Id].label } else { $Id } }
    $Measurable = { param($Id) $CapById.ContainsKey($Id) -and -not [string]::IsNullOrWhiteSpace([string]$CapById[$Id].signal) }

    # ------------------------------------------------------------------ prices + catalog products
    $PriceBySku = @{}
    foreach ($Price in @(Get-CIPPLicensePrice -Currency $Currency)) {
        if ($Price.skuId) { $PriceBySku[([string]$Price.skuId).ToLowerInvariant()] = $Price }
    }
    $PriceOf = {
        param($Sku)
        $Key = ([string]$Sku).ToLowerInvariant()
        if ($PriceBySku.ContainsKey($Key) -and $null -ne $PriceBySku[$Key].MonthlyPrice) { return [double]$PriceBySku[$Key].MonthlyPrice }
        return $null
    }
    $ProductBySku = @{}
    foreach ($Product in @($Catalog.products)) {
        $Key = ([string]$Product.skuId).ToLowerInvariant()
        $ProductBySku[$Key] = [pscustomobject]@{
            skuId          = $Key
            # Names come from the SKU list via the price resolver; the catalog holds no names.
            name           = if ($PriceBySku.ContainsKey($Key) -and $PriceBySku[$Key].Product_Display_Name) { [string]$PriceBySku[$Key].Product_Display_Name } elseif ($Product.name) { [string]$Product.name } else { $Key }
            family         = [string]$Product.family
            tier           = [int]$Product.tier
            eligibleTarget = [bool]$Product.eligibleTarget
            price          = & $PriceOf $Key
            caps           = & $CapsOfPlans (& $GetPlanSet $Key) $null
        }
    }
    $SeatLimits = @{}
    if ($Catalog.meta.seatLimits) { foreach ($P in $Catalog.meta.seatLimits.PSObject.Properties) { $SeatLimits[[string]$P.Name] = [int]$P.Value } }

    # ------------------------------------------------------------------ SKU info from the overview
    $SkuInfo = @{}
    foreach ($Lic in $Licenses) {
        if (-not $Lic.skuId) { continue }
        $Key = ([string]$Lic.skuId).ToLowerInvariant()
        $Total = [int]($Lic.TotalLicenses -as [int])
        $Used = [int]($Lic.CountUsed -as [int])
        $SkuInfo[$Key] = [pscustomobject]@{
            skuId    = $Key
            License  = if ($Lic.License) { [string]$Lic.License } elseif ($ProductBySku.ContainsKey($Key)) { $ProductBySku[$Key].name } else { $Key }
            Total    = $Total
            Used     = $Used
            TermInfo = @($Lic.TermInfo)
        }
    }
    $NameOf = {
        param($Sku)
        $Key = ([string]$Sku).ToLowerInvariant()
        if ($SkuInfo.ContainsKey($Key)) { return $SkuInfo[$Key].License }
        if ($ProductBySku.ContainsKey($Key)) { return $ProductBySku[$Key].name }
        if ($PriceBySku.ContainsKey($Key) -and $PriceBySku[$Key].Product_Display_Name) { return [string]$PriceBySku[$Key].Product_Display_Name }
        return $Key
    }

    # ------------------------------------------------------------------ usage signals per user
    $ParseDate = {
        param($Value)
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
        $Parsed = [datetime]::MinValue
        if ([datetime]::TryParse([string]$Value, [ref]$Parsed)) { return $Parsed }
        return $null
    }
    $Recent = { param($Value) $D = & $ParseDate $Value; ($null -ne $D) -and ($D -ge $Cutoff) }

    $ActivityByUpn = @{}
    foreach ($Row in $ActivityDetail) { if ($Row.userPrincipalName) { $ActivityByUpn[([string]$Row.userPrincipalName).ToLowerInvariant()] = $Row } }
    $AppByUpn = @{}
    foreach ($Row in $AppUsage) { if ($Row.userPrincipalName) { $AppByUpn[([string]$Row.userPrincipalName).ToLowerInvariant()] = $Row } }
    $MailboxByUpn = @{}
    foreach ($Row in $MailboxUsage) { if ($Row.userPrincipalName) { $MailboxByUpn[([string]$Row.userPrincipalName).ToLowerInvariant()] = $Row } }
    $CopilotByUpn = @{}
    foreach ($Row in $CopilotUsage) { if ($Row.userPrincipalName) { $CopilotByUpn[([string]$Row.userPrincipalName).ToLowerInvariant()] = $Row } }

    # Real (member, non-resource, licensed) users
    $RealUsers = @($Users | Where-Object {
            $_.assignedLicenses -and @($_.assignedLicenses).Count -gt 0 -and
            $_.userType -ne 'Guest' -and $_.isResourceAccount -ne $true
        })
    $LicensedUserCount = $RealUsers.Count

    # Anonymized usage reports: rows exist but almost none join to a real user
    $AnonymizedReports = $false
    if ($ActivityByUpn.Count -gt 0 -and $RealUsers.Count -gt 0) {
        $MatchCount = @($RealUsers | Where-Object { $ActivityByUpn.ContainsKey(([string]$_.userPrincipalName).ToLowerInvariant()) }).Count
        if (($MatchCount / [double]$RealUsers.Count) -lt 0.1) { $AnonymizedReports = $true }
    }

    # Which measurable capabilities a user demonstrably used in the window. $null = no usage
    # data for this user at all (the report then makes no claim about them).
    $UsedCapsOf = {
        param($Upn)
        $Key = ([string]$Upn).ToLowerInvariant()
        $Activity = $ActivityByUpn[$Key]
        $Apps = $AppByUpn[$Key]
        if (-not $Activity -and -not $Apps) { return $null }
        $Used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($Activity) {
            if (& $Recent $Activity.exchangeLastActivityDate) { $null = $Used.Add('email') }
            if (& $Recent $Activity.teamsLastActivityDate) { $null = $Used.Add('teams') }
            if ((& $Recent $Activity.oneDriveLastActivityDate) -or (& $Recent $Activity.sharePointLastActivityDate)) { $null = $Used.Add('files') }
        }
        if ($Apps) {
            $Detail = @($Apps.details) | Select-Object -First 1
            if ($Detail -and (($Detail.windows -eq $true) -or ($Detail.mac -eq $true))) { $null = $Used.Add('desktopApps') }
        }
        $Mailbox = $MailboxByUpn[$Key]
        if ($Mailbox) {
            $Bytes = [double]($Mailbox.storageUsedInBytes -as [double])
            if ($Mailbox.hasArchive -eq $true -or $Bytes -gt 40GB) { $null = $Used.Add('largeMailbox'); $null = $Used.Add('email') }
        }
        $Copilot = $CopilotByUpn[$Key]
        if ($Copilot -and (& $Recent $Copilot.lastActivityDate)) { $null = $Used.Add('copilot') }
        return , $Used
    }

    $LastSignInOf = {
        param($User)
        $Last = $null
        foreach ($Prop in @('lastSignInDateTime', 'lastNonInteractiveSignInDateTime')) {
            $D = & $ParseDate $User.signInActivity.$Prop
            if ($D -and ($null -eq $Last -or $D -gt $Last)) { $Last = $D }
        }
        return $Last
    }

    # ------------------------------------------------------------------ waste tiers (existing engine)
    $Optimization = Get-CIPPLicenseOptimization -TenantFilter $TenantFilter -Licenses $Licenses -Users $Users -ActivityDetail $ActivityDetail -InactiveDays $InactiveDays -Currency $Currency

    # Tenant-level SKUs (extra file storage, server protection, capacity) are consumed without a
    # user assignment, so their unassigned seats are not waste. Drop those findings and recount.
    $TenantLevel = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Id in @($Catalog.meta.tenantLevelSkus)) { if ($Id) { $null = $TenantLevel.Add([string]$Id) } }
    $Opportunities = @($Optimization.Opportunities | Where-Object { -not ($_.Tier -eq 'UnassignedSeats' -and $TenantLevel.Contains([string]$_.skuId)) })
    $OptReclaimableMonthly = 0.0; $OptReclaimableSeats = 0
    foreach ($Opp in $Opportunities) {
        $OptReclaimableMonthly += [double]$Opp.MonthlySaving
        if ($Opp.Tier -in @('UnassignedSeats', 'DisabledAccount', 'Inactive')) { $OptReclaimableSeats += [int]$Opp.Seats }
    }
    $Optimization = [pscustomobject]@{ Summary = $Optimization.Summary; Opportunities = $Opportunities }
    $OverlapUpns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Opp in @($Optimization.Opportunities)) {
        if ($Opp.Tier -eq 'Overlap') { foreach ($U in @($Opp.Users)) { $null = $OverlapUpns.Add([string]$U) } }
    }

    # Users the recommendation passes look at: enabled and active in the window. Disabled and
    # stale accounts are already a removal finding.
    #
    # Sign-in dates need Entra ID P1; a tenant without it has no signInActivity at all. There the
    # usage reports (Exchange, Teams, OneDrive, SharePoint, Viva Engage last-activity dates, no P1
    # needed) are the activity signal: a user with a report row and no activity in the window is
    # inactive, and becomes its own removal finding below.
    $ActiveUsers = [System.Collections.Generic.List[object]]::new()
    $NoActivityUsers = [System.Collections.Generic.List[object]]::new()
    $ActivityProps = @('exchangeLastActivityDate', 'teamsLastActivityDate', 'oneDriveLastActivityDate', 'sharePointLastActivityDate', 'yammerLastActivityDate')
    foreach ($User in $RealUsers) {
        if ($User.accountEnabled -eq $false) { continue }
        $Last = & $LastSignInOf $User
        if ($null -ne $Last -and $Last -lt $Cutoff) { continue }
        if ($null -eq $Last -and -not $AnonymizedReports) {
            $Activity = $ActivityByUpn[([string]$User.userPrincipalName).ToLowerInvariant()]
            if ($Activity) {
                $Seen = $false
                foreach ($Prop in $ActivityProps) { if (& $Recent $Activity.$Prop) { $Seen = $true; break } }
                if (-not $Seen) { $NoActivityUsers.Add($User); continue }
            }
        }
        $ActiveUsers.Add($User)
    }

    # Target eligibility: priced, cheaper than the seats it replaces, allowed for this user, and
    # within the family seat limit.
    $IsEligibleTarget = {
        param($Product, $CurrentFamilies)
        if ($null -eq $Product.price) { return $false }
        if (-not $Product.eligibleTarget -and -not ($CurrentFamilies -contains $Product.family)) { return $false }
        if ($SeatLimits.ContainsKey($Product.family) -and $LicensedUserCount -gt $SeatLimits[$Product.family] -and -not ($CurrentFamilies -contains $Product.family)) { return $false }
        return $true
    }
    $CheapestCovering = {
        param($Required, $CurrentFamilies, $MaxPrice)
        $Best = $null
        foreach ($Product in $ProductBySku.Values) {
            if (-not (& $IsEligibleTarget $Product $CurrentFamilies)) { continue }
            if ($Product.price -ge $MaxPrice) { continue }
            if (-not $Product.caps.IsSupersetOf($Required)) { continue }
            if ($null -eq $Best -or $Product.price -lt $Best.price -or ($Product.price -eq $Best.price -and $Product.caps.Count -gt $Best.caps.Count)) { $Best = $Product }
        }
        return $Best
    }

    # ------------------------------------------------------------------ downgrades
    $DowngradeGroups = @{}
    $DowngradeUserCount = 0
    if ($RecommendDowngrades -and -not $AnonymizedReports) {
        foreach ($User in $ActiveUsers) {
            $Upn = [string]$User.userPrincipalName
            $Used = & $UsedCapsOf $Upn
            if ($null -eq $Used) { continue }
            foreach ($Assigned in @($User.assignedLicenses)) {
                if (-not $Assigned.skuId) { continue }
                $Key = ([string]$Assigned.skuId).ToLowerInvariant()
                if (-not $ProductBySku.ContainsKey($Key)) { continue }
                $Current = $ProductBySku[$Key]
                if ($null -eq $Current.price) { continue }
                $Disabled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($D in @($Assigned.disabledPlans)) { if ($D) { $null = $Disabled.Add(([string]$D).ToLowerInvariant()) } }
                $Held = & $CapsOfPlans (& $GetPlanSet $Key) $Disabled
                if ($Held.Count -eq 0) { continue }

                $Required = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $UsedHere = [System.Collections.Generic.List[string]]::new()
                $HasUnmeasurable = $false
                foreach ($CapId in $Held) {
                    if (& $Measurable $CapId) {
                        if ($Used.Contains($CapId)) { $null = $Required.Add($CapId); $UsedHere.Add($CapId) }
                    } else {
                        $HasUnmeasurable = $true
                        if ($ProtectSecurityFeatures) { $null = $Required.Add($CapId) }
                    }
                }

                $Target = $null
                $TargetKey = 'none'
                if ($Required.Count -eq 0) {
                    # Nothing this plan provides is in evidence: remove it (or, when security
                    # features are protected and present, nothing can be said).
                    if ($HasUnmeasurable -and $ProtectSecurityFeatures) { continue }
                } else {
                    $Target = & $CheapestCovering $Required @($Current.family) $Current.price
                    if ($null -eq $Target) { continue }
                    $TargetKey = $Target.skuId
                }

                $Saving = if ($Target) { $Current.price - $Target.price } else { $Current.price }
                $GroupKey = "$Key|$TargetKey"
                if (-not $DowngradeGroups.ContainsKey($GroupKey)) {
                    $Lost = [System.Collections.Generic.List[string]]::new()
                    $Kept = [System.Collections.Generic.List[string]]::new()
                    foreach ($CapId in ($Held | Sort-Object)) {
                        if ($Target -and $Target.caps.Contains($CapId)) { $Kept.Add((& $CapLabel $CapId)) } else { $Lost.Add((& $CapLabel $CapId)) }
                    }
                    $DowngradeGroups[$GroupKey] = [pscustomobject]@{
                        FromLicense   = $Current.name
                        FromSkuId     = $Key
                        ToLicense     = if ($Target) { $Target.name } else { 'No license' }
                        ToSkuId       = if ($Target) { $Target.skuId } else { $null }
                        Action        = if ($Target) { 'Downgrade' } else { 'Remove' }
                        Seats         = 0
                        UnitCost      = $Current.price
                        TargetCost    = if ($Target) { $Target.price } else { 0 }
                        UnitSaving    = [math]::Round($Saving, 2)
                        MonthlySaving = 0.0
                        Keeps         = @($Kept)
                        Loses         = @($Lost)
                        Users         = [System.Collections.Generic.List[object]]::new()
                    }
                }
                $Group = $DowngradeGroups[$GroupKey]
                $Group.Seats = $Group.Seats + 1
                $Group.MonthlySaving = [math]::Round($Group.MonthlySaving + $Saving, 2)
                $Group.Users.Add([pscustomobject]@{ userPrincipalName = $Upn; displayName = [string]$User.displayName; usedCapabilities = @($UsedHere | ForEach-Object { & $CapLabel $_ }) })
                $DowngradeUserCount++
            }
        }
    }
    $Downgrades = @($DowngradeGroups.Values | ForEach-Object { $_.Users = @($_.Users); $_ } | Sort-Object -Property MonthlySaving -Descending)

    # ------------------------------------------------------------------ upgrades
    $UpgradeGroups = @{}
    $ProtectCaps = [System.Collections.Generic.HashSet[string]]::new([string[]]@('deviceManagement', 'signInSecurity', 'endpointSecurity'), [System.StringComparer]::OrdinalIgnoreCase)
    if ($RecommendUpgrades) {
        foreach ($User in $ActiveUsers) {
            $Upn = [string]$User.userPrincipalName
            $HeldProducts = [System.Collections.Generic.List[object]]::new()
            $UnionCaps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $Families = [System.Collections.Generic.List[string]]::new()
            $Sum = 0.0
            $Unpriced = $false
            foreach ($Assigned in @($User.assignedLicenses)) {
                if (-not $Assigned.skuId) { continue }
                $Key = ([string]$Assigned.skuId).ToLowerInvariant()
                if (-not $ProductBySku.ContainsKey($Key)) { $Unpriced = $true; continue }
                $Product = $ProductBySku[$Key]
                if ($null -eq $Product.price) { $Unpriced = $true; continue }
                $HeldProducts.Add($Product)
                $Families.Add($Product.family)
                $Sum += $Product.price
                $Disabled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($D in @($Assigned.disabledPlans)) { if ($D) { $null = $Disabled.Add(([string]$D).ToLowerInvariant()) } }
                $UnionCaps.UnionWith((& $CapsOfPlans (& $GetPlanSet $Key) $Disabled))
            }
            if ($HeldProducts.Count -eq 0 -or $Unpriced) { continue }
            $FromNames = @($HeldProducts | Sort-Object -Property name | Select-Object -ExpandProperty name -Unique)
            $FromKey = ($HeldProducts.skuId | Sort-Object) -join '+'

            # Consolidate: several plans -> one cheaper plan covering the same capabilities
            if ($HeldProducts.Count -ge 2 -and -not $OverlapUpns.Contains($Upn)) {
                $Target = & $CheapestCovering $UnionCaps @($Families) $Sum
                if ($Target) {
                    $GroupKey = "Consolidate|$FromKey|$($Target.skuId)"
                    if (-not $UpgradeGroups.ContainsKey($GroupKey)) {
                        $UpgradeGroups[$GroupKey] = [pscustomobject]@{
                            Type          = 'Consolidate'
                            FromLicenses  = $FromNames
                            FromSkuIds    = @($HeldProducts.skuId)
                            ToLicense     = $Target.name
                            ToSkuId       = $Target.skuId
                            Seats         = 0
                            UnitCost      = [math]::Round($Sum, 2)
                            TargetCost    = $Target.price
                            UnitDelta     = [math]::Round($Target.price - $Sum, 2)
                            MonthlyDelta  = 0.0
                            Gains         = @(($Target.caps | Where-Object { -not $UnionCaps.Contains($_) } | Sort-Object) | ForEach-Object { & $CapLabel $_ })
                            Users         = [System.Collections.Generic.List[object]]::new()
                        }
                    }
                    $Group = $UpgradeGroups[$GroupKey]
                    $Group.Seats = $Group.Seats + 1
                    $Group.MonthlyDelta = [math]::Round($Group.MonthlyDelta + ($Target.price - $Sum), 2)
                    $Group.Users.Add([pscustomobject]@{ userPrincipalName = $Upn; displayName = [string]$User.displayName })
                }
            }

            # Protect: no device management / sign-in security / device threat protection at all
            if (-not $UnionCaps.Overlaps($ProtectCaps)) {
                $Required = [System.Collections.Generic.HashSet[string]]::new($UnionCaps, [System.StringComparer]::OrdinalIgnoreCase)
                $Required.UnionWith($ProtectCaps)
                $Target = & $CheapestCovering $Required @($Families) ([double]::MaxValue)
                if ($Target) {
                    $GroupKey = "Protect|$FromKey|$($Target.skuId)"
                    if (-not $UpgradeGroups.ContainsKey($GroupKey)) {
                        $UpgradeGroups[$GroupKey] = [pscustomobject]@{
                            Type          = 'Protect'
                            FromLicenses  = $FromNames
                            FromSkuIds    = @($HeldProducts.skuId)
                            ToLicense     = $Target.name
                            ToSkuId       = $Target.skuId
                            Seats         = 0
                            UnitCost      = [math]::Round($Sum, 2)
                            TargetCost    = $Target.price
                            UnitDelta     = [math]::Round($Target.price - $Sum, 2)
                            MonthlyDelta  = 0.0
                            Gains         = @(($Target.caps | Where-Object { -not $UnionCaps.Contains($_) } | Sort-Object) | ForEach-Object { & $CapLabel $_ })
                            Users         = [System.Collections.Generic.List[object]]::new()
                        }
                    }
                    $Group = $UpgradeGroups[$GroupKey]
                    $Group.Seats = $Group.Seats + 1
                    $Group.MonthlyDelta = [math]::Round($Group.MonthlyDelta + ($Target.price - $Sum), 2)
                    $Group.Users.Add([pscustomobject]@{ userPrincipalName = $Upn; displayName = [string]$User.displayName })
                }
            }
        }
    }
    $Upgrades = @($UpgradeGroups.Values | ForEach-Object { $_.Users = @($_.Users); $_ } | Sort-Object -Property @{ Expression = 'Type' }, @{ Expression = 'MonthlyDelta' })

    # ------------------------------------------------------------------ terms (annual vs monthly)
    $Terms = [System.Collections.Generic.List[object]]::new()
    if ($RecommendTerms) {
        $TenureCutoff = $Now.AddMonths(-$TenureMonths)
        # skuId -> count of stable assignments among active users
        $StableBySku = @{}
        $AssignedActiveBySku = @{}
        foreach ($User in $ActiveUsers) {
            $Created = & $ParseDate $User.createdDateTime
            $StateBySku = @{}
            foreach ($State in @($User.licenseAssignmentStates)) {
                if (-not $State.skuId) { continue }
                if ($State.state -and $State.state -ne 'Active') { continue }
                $StateBySku[([string]$State.skuId).ToLowerInvariant()] = $State
            }
            foreach ($Assigned in @($User.assignedLicenses)) {
                if (-not $Assigned.skuId) { continue }
                $Key = ([string]$Assigned.skuId).ToLowerInvariant()
                if (-not $AssignedActiveBySku.ContainsKey($Key)) { $AssignedActiveBySku[$Key] = 0; $StableBySku[$Key] = 0 }
                $AssignedActiveBySku[$Key] = $AssignedActiveBySku[$Key] + 1
                $Since = $null
                if ($StateBySku.ContainsKey($Key)) { $Since = & $ParseDate $StateBySku[$Key].lastUpdatedDateTime }
                if ($null -eq $Since) { $Since = $Created }
                if ($null -ne $Since -and $Since -le $TenureCutoff) { $StableBySku[$Key] = $StableBySku[$Key] + 1 }
            }
        }
        foreach ($Sku in $SkuInfo.Values) {
            if ($Sku.Used -le 0 -and $Sku.Total -le 0) { continue }
            if ($TenantLevel.Contains($Sku.skuId)) { continue }
            $UnitPrice = & $PriceOf $Sku.skuId
            $MonthlySeats = 0; $YearlySeats = 0; $UnknownSeats = 0; $NextRenewal = $null
            foreach ($Term in @($Sku.TermInfo)) {
                if ($null -eq $Term) { continue }
                if ($Term.Status -and $Term.Status -notin @('Enabled', 'Warning')) { continue }
                $Seats = [int]($Term.TotalLicenses -as [int])
                switch ([string]$Term.Term) {
                    'Monthly' { $MonthlySeats += $Seats }
                    'Yearly' { $YearlySeats += $Seats }
                    '3 Year' { $YearlySeats += $Seats }
                    default { $UnknownSeats += $Seats }
                }
                $Days = $Term.DaysUntilRenew -as [int]
                if ($null -ne $Days -and ($null -eq $NextRenewal -or $Days -lt $NextRenewal)) { $NextRenewal = $Days }
            }
            $Stable = if ($StableBySku.ContainsKey($Sku.skuId)) { [int]$StableBySku[$Sku.skuId] } else { 0 }
            $Assigned = [int]$Sku.Used
            $RecommendedAnnual = [math]::Min($Stable, $Assigned)
            $RecommendedMonthly = [math]::Max(0, $Assigned - $RecommendedAnnual)
            $TermKnown = ($MonthlySeats + $YearlySeats) -gt 0
            $Convertible = if ($TermKnown) { [math]::Max(0, [math]::Min($MonthlySeats, $RecommendedAnnual - $YearlySeats)) } else { $null }
            $Saving = if ($TermKnown -and $null -ne $UnitPrice) { [math]::Round($Convertible * $UnitPrice * $Uplift, 2) } else { 0.0 }
            $LockedUnused = if ($TermKnown) { [math]::Max(0, $YearlySeats - $Assigned) } else { 0 }
            $Terms.Add([pscustomobject]@{
                    License            = $Sku.License
                    skuId              = $Sku.skuId
                    TotalSeats         = [int]$Sku.Total
                    AssignedSeats      = $Assigned
                    StableSeats        = $Stable
                    MonthlySeats       = $MonthlySeats
                    YearlySeats        = $YearlySeats
                    UnknownTermSeats   = $UnknownSeats
                    TermKnown          = $TermKnown
                    RecommendedAnnual  = $RecommendedAnnual
                    RecommendedMonthly = $RecommendedMonthly
                    ConvertibleSeats   = $Convertible
                    UnitCost           = $UnitPrice
                    MonthlySaving      = $Saving
                    LockedUnusedSeats  = $LockedUnused
                    NextRenewalDays    = $NextRenewal
                    PriceKnown         = ($null -ne $UnitPrice)
                })
        }
    }
    $Terms = @($Terms | Sort-Object -Property MonthlySaving -Descending)

    # ------------------------------------------------------------------ products (what is paid for)
    $Products = [System.Collections.Generic.List[object]]::new()
    foreach ($Sku in $SkuInfo.Values) {
        $UnitPrice = & $PriceOf $Sku.skuId
        $Caps = & $CapsOfPlans (& $GetPlanSet $Sku.skuId) $null
        $Products.Add([pscustomobject]@{
                License      = $Sku.License
                skuId        = $Sku.skuId
                Family       = if ($ProductBySku.ContainsKey($Sku.skuId)) { $ProductBySku[$Sku.skuId].family } else { $null }
                TotalSeats   = [int]$Sku.Total
                AssignedSeats = [int]$Sku.Used
                UnusedSeats  = if ($TenantLevel.Contains($Sku.skuId)) { 0 } else { [math]::Max(0, [int]$Sku.Total - [int]$Sku.Used) }
                TenantLevel  = $TenantLevel.Contains($Sku.skuId)
                UnitCost     = $UnitPrice
                MonthlySpend = if ($null -ne $UnitPrice) { [math]::Round($UnitPrice * [int]$Sku.Used, 2) } else { $null }
                PriceKnown   = ($null -ne $UnitPrice)
                Capabilities = @($Caps | Sort-Object | ForEach-Object { & $CapLabel $_ })
            })
    }
    $Products = @($Products | Sort-Object -Property @{ Expression = 'MonthlySpend'; Descending = $true }, 'License')

    # ------------------------------------------------------------------ flat suggestion list
    # One row per action someone can take: "remove the license from X because Y". Seat-level
    # findings (unassigned seats, term changes) have no user. The mailbox-only review tier is left
    # out: the evidence-based downgrade pass above supersedes it.
    $Suggestions = [System.Collections.Generic.List[object]]::new()
    $UserByUpn = @{}
    foreach ($User in $RealUsers) { if ($User.userPrincipalName) { $UserByUpn[([string]$User.userPrincipalName).ToLowerInvariant()] = $User } }
    $UpliftPct = [int][math]::Round($Uplift * 100)
    $AddSuggestion = {
        param($Type, $Upn, $License, $Sku, $Target, $Suggestion, $Reason, $Seats, $Saving, $PriceKnown, $Evidence, $Loses)
        $User = if ($Upn) { $UserByUpn[([string]$Upn).ToLowerInvariant()] } else { $null }
        $Monthly = [math]::Round([double]$Saving, 2)
        $Suggestions.Add([pscustomobject]@{
                Type          = $Type
                User          = [string]$Upn
                UserId        = if ($User) { [string]$User.id } else { '' }
                DisplayName   = if ($User) { [string]$User.displayName } else { '' }
                License       = [string]$License
                skuId         = ([string]$Sku).ToLowerInvariant()
                TargetLicense = [string]$Target
                Suggestion    = $Suggestion
                Reason        = $Reason
                Seats         = [int]$Seats
                MonthlySaving = $Monthly
                AnnualSaving  = [math]::Round($Monthly * 12, 2)
                PriceKnown    = [bool]$PriceKnown
                Evidence      = @($Evidence)
                Loses         = @($Loses)
            })
    }
    foreach ($Opp in @($Optimization.Opportunities)) {
        $Unit = if ($null -ne $Opp.UnitCost) { [double]$Opp.UnitCost } else { 0.0 }
        switch ([string]$Opp.Tier) {
            'UnassignedSeats' {
                & $AddSuggestion 'Reduce seats' '' $Opp.License $Opp.skuId '' "Reduce the seat count by $($Opp.Seats)" "$($Opp.Seats) seats are bought but assigned to nobody" $Opp.Seats $Opp.MonthlySaving $Opp.PriceKnown @() @()
            }
            'DisabledAccount' {
                foreach ($Upn in @($Opp.Users)) { & $AddSuggestion 'Remove license' $Upn $Opp.License $Opp.skuId '' "Remove $($Opp.License)" 'The account is disabled' 1 $Unit $Opp.PriceKnown @() @() }
            }
            'Inactive' {
                foreach ($Upn in @($Opp.Users)) {
                    $User = $UserByUpn[([string]$Upn).ToLowerInvariant()]
                    $Last = if ($User) { & $LastSignInOf $User } else { $null }
                    $Reason = if ($Last) { 'No sign-in for {0} days (last sign-in {1:yyyy-MM-dd})' -f [int]($Now - $Last).TotalDays, $Last } else { "No sign-in for more than $InactiveDays days" }
                    & $AddSuggestion 'Remove license' $Upn $Opp.License $Opp.skuId '' "Remove $($Opp.License)" $Reason 1 $Unit $Opp.PriceKnown @() @()
                }
            }
            'Overlap' {
                foreach ($Upn in @($Opp.Users)) { & $AddSuggestion 'Remove license' $Upn $Opp.License $Opp.skuId '' "Remove $($Opp.License)" 'Another assigned license already includes everything this one provides' 1 $Unit $Opp.PriceKnown @() @() }
            }
        }
    }
    # No sign-in data (no Entra ID P1) and nothing used in the window: remove every priced license
    $NoActivityMonthly = 0.0
    $NoActivitySeats = 0
    foreach ($User in $NoActivityUsers) {
        foreach ($Assigned in @($User.assignedLicenses)) {
            if (-not $Assigned.skuId) { continue }
            $Key = ([string]$Assigned.skuId).ToLowerInvariant()
            $Unit = & $PriceOf $Key
            $Name = & $NameOf $Key
            & $AddSuggestion 'Remove license' $User.userPrincipalName $Name $Key '' "Remove $Name" "No activity in email, Teams, OneDrive or SharePoint for $InactiveDays days (sign-in dates need Entra ID P1, which this tenant does not report)" 1 ($Unit ?? 0) ($null -ne $Unit) @() @()
            $NoActivityMonthly += ($Unit ?? 0)
            $NoActivitySeats++
        }
    }

    foreach ($D in $Downgrades) {
        foreach ($U in @($D.Users)) {
            $Used = @($U.usedCapabilities)
            $Reason = if ($Used.Count -gt 0) { "Used only $($Used -join ', ') in the last $InactiveDays days" } else { "Nothing this license provides was used in the last $InactiveDays days" }
            if (@($D.Loses).Count -gt 0 -and $D.Action -ne 'Remove') { $Reason += "; would lose $(@($D.Loses) -join ', ')" }
            if ($D.Action -eq 'Remove') {
                & $AddSuggestion 'Remove license' $U.userPrincipalName $D.FromLicense $D.FromSkuId '' "Remove $($D.FromLicense)" $Reason 1 $D.UnitSaving $true $Used $D.Loses
            } else {
                & $AddSuggestion 'Change license' $U.userPrincipalName $D.FromLicense $D.FromSkuId $D.ToLicense "Change $($D.FromLicense) to $($D.ToLicense)" $Reason 1 $D.UnitSaving $true $Used $D.Loses
            }
        }
    }
    foreach ($Up in $Upgrades) {
        foreach ($U in @($Up.Users)) {
            $From = @($Up.FromLicenses) -join ' + '
            if ($Up.Type -eq 'Consolidate') {
                & $AddSuggestion 'Combine licenses' $U.userPrincipalName $From $Up.FromSkuIds[0] $Up.ToLicense "Replace $From with $($Up.ToLicense)" 'One bundle covers the same features for less' 1 (-1 * [double]$Up.UnitDelta) $true @() @()
            } else {
                & $AddSuggestion 'Add protection' $U.userPrincipalName $From $Up.FromSkuIds[0] $Up.ToLicense "Change $From to $($Up.ToLicense)" "No device management, sign-in security or device threat protection; adds $(@($Up.Gains) -join ', ')" 1 (-1 * [double]$Up.UnitDelta) $true @() @()
            }
        }
    }
    foreach ($T in $Terms) {
        if ($null -ne $T.ConvertibleSeats -and [int]$T.ConvertibleSeats -gt 0) {
            & $AddSuggestion 'Change term' '' $T.License $T.skuId '' "Move $($T.ConvertibleSeats) seats to a yearly commitment" "$($T.StableSeats) of $($T.AssignedSeats) assigned seats have been held for $TenureMonths+ months; a monthly commitment costs $UpliftPct% more" $T.ConvertibleSeats $T.MonthlySaving $T.PriceKnown @() @()
        }
    }
    $Suggestions = @($Suggestions | Sort-Object -Property @{ Expression = 'MonthlySaving'; Descending = $true }, 'User')

    # ------------------------------------------------------------------ summary
    $DowngradeMonthly = 0.0; foreach ($D in $Downgrades) { $DowngradeMonthly += [double]$D.MonthlySaving }
    $ConsolidateMonthly = 0.0; $ProtectMonthly = 0.0; $ProtectSeats = 0
    foreach ($U in $Upgrades) {
        if ($U.Type -eq 'Consolidate') { $ConsolidateMonthly += -1 * [double]$U.MonthlyDelta } else { $ProtectMonthly += [double]$U.MonthlyDelta; $ProtectSeats += [int]$U.Seats }
    }
    $TermMonthly = 0.0; foreach ($T in $Terms) { $TermMonthly += [double]$T.MonthlySaving }
    $Reclaimable = $OptReclaimableMonthly + $NoActivityMonthly
    $TotalSeats = 0; foreach ($Sku in $SkuInfo.Values) { $TotalSeats += [int]$Sku.Total }
    $TotalMonthly = $Reclaimable + $DowngradeMonthly + $ConsolidateMonthly + $TermMonthly

    $Summary = [pscustomobject]@{
        Tenant                    = $TenantFilter
        Currency                  = $Currency
        GeneratedAt               = $Now.ToString('o')
        ReportPeriodDays          = 90
        InactiveDays              = $InactiveDays
        TenureMonths              = $TenureMonths
        RecommendDowngrades       = $RecommendDowngrades
        RecommendUpgrades         = $RecommendUpgrades
        RecommendTerms            = $RecommendTerms
        ProtectSecurityFeatures   = $ProtectSecurityFeatures
        MonthlySpend              = [double]$Optimization.Summary.MonthlySpend
        AssignedSeats             = [int]$Optimization.Summary.AssignedSeats
        TotalSeats                = $TotalSeats
        LicensedUsers             = $LicensedUserCount
        PriceCoverage             = $Optimization.Summary.PriceCoverage
        ReclaimableMonthly        = [math]::Round($Reclaimable, 2)
        ReclaimableSeats          = $OptReclaimableSeats + $NoActivitySeats
        SignInDataAvailable       = [bool](@($RealUsers | Where-Object { $null -ne (& $LastSignInOf $_) }).Count -gt 0)
        DowngradeMonthly          = [math]::Round($DowngradeMonthly, 2)
        DowngradeSeats            = $DowngradeUserCount
        ConsolidationMonthly      = [math]::Round($ConsolidateMonthly, 2)
        TermMonthly               = [math]::Round($TermMonthly, 2)
        ProtectInvestmentMonthly  = [math]::Round($ProtectMonthly, 2)
        ProtectSeats              = $ProtectSeats
        TotalPotentialMonthly     = [math]::Round($TotalMonthly, 2)
        TotalPotentialAnnual      = [math]::Round($TotalMonthly * 12, 2)
        MonthlyCommitmentUplift   = $Uplift
        SuggestionCount           = $Suggestions.Count
        AnonymizedReports         = $AnonymizedReports
        DataAvailable             = ($Licenses.Count -gt 0)
        UsageDataAvailable        = ($ActivityDetail.Count -gt 0)
        AppUsageDataAvailable     = ($AppUsage.Count -gt 0)
        MailboxUsageDataAvailable = ($MailboxUsage.Count -gt 0)
        Sources                   = [pscustomobject]$Sources
    }

    return [pscustomobject]@{
        Summary      = $Summary
        Suggestions  = $Suggestions
        Optimization = $Optimization
        Downgrades   = $Downgrades
        Upgrades     = $Upgrades
        Terms        = $Terms
        Products     = $Products
        Capabilities = @($Capabilities | ForEach-Object { [pscustomobject]@{ id = $_.id; label = $_.label; description = $_.description; measurable = (-not [string]::IsNullOrWhiteSpace([string]$_.signal)) } })
    }
}

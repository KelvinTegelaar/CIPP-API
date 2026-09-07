function Get-CIPPLicenseOptimization {
    <#
    .SYNOPSIS
        Compute license waste and reclaimable spend for a tenant.

    .DESCRIPTION
        Joins the cached license overview, users, and active-user-detail datasets with the resolved
        price map (Get-CIPPLicensePrice) to produce a per-tenant optimization report: a monetary
        summary plus a list of reclaim opportunities across five tiers:

        1. UnassignedSeats  - owned seats no one holds (CountAvailable > 0)
        2. DisabledAccount  - a license assigned to a disabled account
        3. Inactive         - a license on an enabled account with no sign-in in -InactiveDays
        4. Downgrade        - a mailbox-only user on a premium SKU (review candidate)
        5. Overlap          - a SKU whose service plans are fully covered by another SKU the user holds

        All inputs default to the reporting-DB cache but can be injected for testing or a live run.

    .PARAMETER TenantFilter
        The tenant (domain or GUID) to report on.

    .PARAMETER Licenses
        Optional. LicenseOverview records. Defaults to the cached 'LicenseOverview' type.

    .PARAMETER Users
        Optional. User records. Defaults to the cached 'Users' type.

    .PARAMETER ActivityDetail
        Optional. getOffice365ActiveUserDetail rows. Defaults to the cached 'ActiveUserDetail' type.

    .PARAMETER InactiveDays
        Sign-in age (days) past which an enabled licensed user counts as inactive. Default 90.

    .PARAMETER Currency
        ISO currency code the money figures are resolved in (passed to Get-CIPPLicensePrice).
        Default USD.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        $Licenses,
        $Users,
        $ActivityDetail,
        [int]$InactiveDays = 90,
        [string]$Currency = 'USD'
    )

    if (-not $PSBoundParameters.ContainsKey('Licenses')) { $Licenses = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'LicenseOverview') }
    if (-not $PSBoundParameters.ContainsKey('Users')) { $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users') }
    if (-not $PSBoundParameters.ContainsKey('ActivityDetail')) { $ActivityDetail = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ActiveUserDetail') }

    $Licenses = @($Licenses)
    $Users = @($Users)
    $ActivityDetail = @($ActivityDetail)

    # --- price map (lowercased skuId -> price object) ---
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

    # --- SKU lookup from the license overview: pretty name, service-plan set, seat counts ---
    $SkuInfo = @{}
    foreach ($Lic in $Licenses) {
        if (-not $Lic.skuId) { continue }
        $Key = ([string]$Lic.skuId).ToLowerInvariant()
        $PlanIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Plan in @($Lic.ServicePlans)) {
            if ($Plan.servicePlanId) { $null = $PlanIds.Add([string]$Plan.servicePlanId) }
        }
        $Total = [int]($Lic.TotalLicenses -as [int])
        $Used = [int]($Lic.CountUsed -as [int])
        $SkuInfo[$Key] = [pscustomobject]@{
            skuId     = $Key
            License   = if ($Lic.License) { [string]$Lic.License } else { $Key }
            PlanIds   = $PlanIds
            Total     = $Total
            Used      = $Used
            Available = $Total - $Used
        }
    }
    $NameOf = {
        param($Sku)
        $Key = ([string]$Sku).ToLowerInvariant()
        if ($SkuInfo.ContainsKey($Key)) { return $SkuInfo[$Key].License }
        if ($PriceBySku.ContainsKey($Key) -and $PriceBySku[$Key].Product_Display_Name) { return [string]$PriceBySku[$Key].Product_Display_Name }
        return $Key
    }

    # --- activity map (lowercased UPN -> row); detect anonymized reports ---
    $ActivityByUpn = @{}
    foreach ($Row in $ActivityDetail) {
        if ($Row.userPrincipalName) { $ActivityByUpn[([string]$Row.userPrincipalName).ToLowerInvariant()] = $Row }
    }
    $Cutoff = (Get-Date).AddDays(-$InactiveDays)
    $ActiveIn = {
        param($Row, $DateProp)
        $Value = $Row.$DateProp
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $false }
        $Parsed = [datetime]::MinValue
        if ([datetime]::TryParse([string]$Value, [ref]$Parsed)) { return $Parsed -ge $Cutoff }
        return $false
    }

    # Real (non-service, non-guest) users only for per-user tiers
    $RealUsers = @($Users | Where-Object {
            $_.assignedLicenses -and @($_.assignedLicenses).Count -gt 0 -and
            $_.userType -ne 'Guest' -and $_.isResourceAccount -ne $true
        })

    # Anonymized when activity exists but almost none of its UPNs match real users
    $AnonymizedReports = $false
    if ($ActivityByUpn.Count -gt 0 -and $RealUsers.Count -gt 0) {
        $MatchCount = @($RealUsers | Where-Object { $ActivityByUpn.ContainsKey(([string]$_.userPrincipalName).ToLowerInvariant()) }).Count
        if (($MatchCount / [double]$RealUsers.Count) -lt 0.1) { $AnonymizedReports = $true }
    }

    $Opportunities = [System.Collections.Generic.List[object]]::new()
    $NewOpportunity = {
        param($Tier, $Finding, $Sku, $Seats, $MonthlySaving, $Action, $Users, $PriceKnown)
        $Monthly = [math]::Round(([double]$MonthlySaving), 2)
        $Opportunities.Add([pscustomobject]@{
                Tier            = $Tier
                FindingLabel    = $Finding
                License         = & $NameOf $Sku
                skuId           = ([string]$Sku).ToLowerInvariant()
                Seats           = [int]$Seats
                UnitCost        = & $PriceOf $Sku
                MonthlySaving   = $Monthly
                SuggestedAction = $Action
                Users           = @($Users)
                PriceKnown      = [bool]$PriceKnown
            })
    }

    # --- Tier 1: unassigned (empty) seats ---
    foreach ($Sku in $SkuInfo.Values) {
        if ($Sku.Available -le 0) { continue }
        $UnitPrice = & $PriceOf $Sku.skuId
        & $NewOpportunity 'UnassignedSeats' 'Unassigned' $Sku.skuId $Sku.Available (($UnitPrice ?? 0) * $Sku.Available) 'Reduce seat count' @() ($null -ne $UnitPrice)
    }

    # --- Tiers 2 & 3: disabled / inactive assigned seats (grouped by SKU) ---
    $DisabledBySku = @{}
    $InactiveBySku = @{}
    foreach ($User in $RealUsers) {
        $Upn = [string]$User.userPrincipalName
        $Disabled = $User.accountEnabled -eq $false

        # Most-recent sign-in (interactive or non-interactive)
        $LastSignIn = $null
        foreach ($Prop in @('lastSignInDateTime', 'lastNonInteractiveSignInDateTime')) {
            $Value = $User.signInActivity.$Prop
            if (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
                $Parsed = [datetime]::MinValue
                if ([datetime]::TryParse([string]$Value, [ref]$Parsed)) {
                    if ($null -eq $LastSignIn -or $Parsed -gt $LastSignIn) { $LastSignIn = $Parsed }
                }
            }
        }
        # Enabled + has a sign-in on record + that sign-in is stale. Never-signed-in enabled
        # accounts are skipped by default to avoid flagging provisioning/service identities.
        $Inactive = (-not $Disabled) -and ($null -ne $LastSignIn) -and ($LastSignIn -lt $Cutoff)

        if (-not $Disabled -and -not $Inactive) { continue }
        $Bucket = if ($Disabled) { $DisabledBySku } else { $InactiveBySku }
        foreach ($Assigned in @($User.assignedLicenses)) {
            if (-not $Assigned.skuId) { continue }
            $Key = ([string]$Assigned.skuId).ToLowerInvariant()
            if (-not $Bucket.ContainsKey($Key)) { $Bucket[$Key] = [System.Collections.Generic.List[string]]::new() }
            $Bucket[$Key].Add($Upn)
        }
    }
    foreach ($Key in $DisabledBySku.Keys) {
        $Upns = $DisabledBySku[$Key]
        $UnitPrice = & $PriceOf $Key
        & $NewOpportunity 'DisabledAccount' 'Disabled user' $Key $Upns.Count (($UnitPrice ?? 0) * $Upns.Count) 'Remove license' $Upns ($null -ne $UnitPrice)
    }
    foreach ($Key in $InactiveBySku.Keys) {
        $Upns = $InactiveBySku[$Key]
        $UnitPrice = & $PriceOf $Key
        & $NewOpportunity 'Inactive' ("Inactive {0}d+" -f $InactiveDays) $Key $Upns.Count (($UnitPrice ?? 0) * $Upns.Count) 'Review / remove' $Upns ($null -ne $UnitPrice)
    }

    # --- Tier 4: mailbox-only users on a premium suite SKU (flag for REVIEW, not a downgrade) ---
    # A user who only uses email yet holds a full suite may be over-licensed - but a licensed
    # (shared) mailbox is sometimes deliberate (large archive, litigation/in-place hold, >50 GB, an
    # auto-mapped resource). So we make no assumption about downgrading and claim no saving; we
    # surface the seats for the MSP to review and decide.
    $ReviewSuiteSkus = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Guid in @(
            '6fd2c87f-b296-42f0-b197-1e91e994b900', # Office 365 E3
            'c7df2760-2c81-4ef7-b578-5b5392b571df', # Office 365 E5
            '05e9a617-0261-4cee-bb44-138d3ef5d965', # Microsoft 365 E3
            '06ebc4ee-1bb5-47dd-8120-11324bc54e06', # Microsoft 365 E5
            'f245ecc8-75af-4f8e-b61f-27d8114de5f3', # Microsoft 365 Business Standard
            'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46'  # Microsoft 365 Business Premium
        )) { $null = $ReviewSuiteSkus.Add($Guid) }

    $ReviewBySku = @{}
    foreach ($User in $RealUsers) {
        if ($User.accountEnabled -eq $false) { continue }
        $Activity = $ActivityByUpn[([string]$User.userPrincipalName).ToLowerInvariant()]
        if (-not $Activity) { continue }
        $UsedExchange = & $ActiveIn $Activity 'exchangeLastActivityDate'
        $UsedCollab = (& $ActiveIn $Activity 'oneDriveLastActivityDate') -or
                      (& $ActiveIn $Activity 'sharePointLastActivityDate') -or
                      (& $ActiveIn $Activity 'teamsLastActivityDate') -or
                      (& $ActiveIn $Activity 'yammerLastActivityDate')
        if (-not $UsedExchange -or $UsedCollab) { continue }
        foreach ($Assigned in @($User.assignedLicenses)) {
            $Key = ([string]$Assigned.skuId).ToLowerInvariant()
            if (-not $ReviewSuiteSkus.Contains($Key)) { continue }
            if (-not $ReviewBySku.ContainsKey($Key)) { $ReviewBySku[$Key] = [System.Collections.Generic.List[string]]::new() }
            $ReviewBySku[$Key].Add([string]$User.userPrincipalName)
        }
    }
    foreach ($Key in $ReviewBySku.Keys) {
        $Upns = $ReviewBySku[$Key]
        # Review only - no assumed downgrade target, so no monetary saving is claimed. PriceKnown
        # still reflects whether the SKU itself is priced (so the UI's set-price action only targets
        # genuinely unpriced SKUs, not these).
        $UnitPrice = & $PriceOf $Key
        & $NewOpportunity 'Downgrade' 'Mailbox-only' $Key $Upns.Count 0 'Review: only using email' $Upns ($null -ne $UnitPrice)
    }

    # --- Tier 5: redundant SKU whose service plans are fully covered by another SKU the user holds ---
    $OverlapBySku = @{}
    foreach ($User in $RealUsers) {
        $Held = @(@($User.assignedLicenses).skuId | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() } | Select-Object -Unique)
        if ($Held.Count -lt 2) { continue }
        foreach ($A in $Held) {
            if (-not $SkuInfo.ContainsKey($A) -or $SkuInfo[$A].PlanIds.Count -eq 0) { continue }
            foreach ($B in $Held) {
                if ($A -eq $B -or -not $SkuInfo.ContainsKey($B)) { continue }
                # A is redundant if every plan in A is also in B (A is a subset of B) and B is larger
                if ($SkuInfo[$B].PlanIds.Count -gt $SkuInfo[$A].PlanIds.Count -and $SkuInfo[$B].PlanIds.IsSupersetOf($SkuInfo[$A].PlanIds)) {
                    if (-not $OverlapBySku.ContainsKey($A)) { $OverlapBySku[$A] = [System.Collections.Generic.List[string]]::new() }
                    $OverlapBySku[$A].Add([string]$User.userPrincipalName)
                    break
                }
            }
        }
    }
    foreach ($Key in $OverlapBySku.Keys) {
        $Upns = @($OverlapBySku[$Key] | Select-Object -Unique)
        $UnitPrice = & $PriceOf $Key
        & $NewOpportunity 'Overlap' 'Redundant' $Key $Upns.Count (($UnitPrice ?? 0) * $Upns.Count) 'Remove redundant license' $Upns ($null -ne $UnitPrice)
    }

    # --- summary --- (money resolved in the requested $Currency)
    $MonthlySpend = 0.0
    $PricedSeats = 0
    $TotalAssignedSeats = 0
    foreach ($Sku in $SkuInfo.Values) {
        $TotalAssignedSeats += $Sku.Used
        $UnitPrice = & $PriceOf $Sku.skuId
        if ($null -ne $UnitPrice) {
            $MonthlySpend += $UnitPrice * $Sku.Used
            $PricedSeats += $Sku.Used
        }
    }
    $ReclaimableMonthly = 0.0
    foreach ($Opp in $Opportunities) { $ReclaimableMonthly += $Opp.MonthlySaving }
    $ReclaimableSeats = 0
    foreach ($Opp in $Opportunities) {
        if ($Opp.Tier -in @('UnassignedSeats', 'DisabledAccount', 'Inactive')) { $ReclaimableSeats += $Opp.Seats }
    }

    $Summary = [pscustomobject]@{
        Tenant             = $TenantFilter
        Currency           = $Currency
        MonthlySpend       = [math]::Round($MonthlySpend, 2)
        ReclaimableMonthly = [math]::Round($ReclaimableMonthly, 2)
        ReclaimableSeats   = $ReclaimableSeats
        AssignedSeats      = $TotalAssignedSeats
        PriceCoverage      = if ($TotalAssignedSeats -gt 0) { [math]::Round($PricedSeats / [double]$TotalAssignedSeats, 3) } else { 0 }
        OpportunityCount   = $Opportunities.Count
        AnonymizedReports  = $AnonymizedReports
        DataAvailable      = ($Licenses.Count -gt 0)
    }

    return [pscustomobject]@{
        Summary       = $Summary
        Opportunities = @($Opportunities | Sort-Object -Property MonthlySaving -Descending)
    }
}

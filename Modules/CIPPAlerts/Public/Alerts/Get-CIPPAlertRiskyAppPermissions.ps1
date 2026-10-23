function Get-CIPPAlertRiskyAppPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .SYNOPSIS
        Alerts on apps (service principals) that hold potentially over-privileged API permissions.
    .DESCRIPTION
        Filters Get-CIPPAppPermissionExposure (cached app role assignments and OAuth2 permission grants
        matched against Config/RiskyPermissions.json) and reports one row per app. CIPP's own SAM app is
        always skipped.

        Inputs: MinimumRisk - Critical, High (default), Medium or Low; RateBy - what MinimumRisk and the sort
        order apply to: Risk (default: the app's context-aware rating, reporting every permission it holds),
        Impact (damage if the app is compromised) or Suspicion (how unusual the permission is), both per
        permission, reporting the permissions at or above the level; Categories - PrivilegeEscalation,
        DataAccess, Integrity and/or Availability (default: all); ExcludeDelegated - skip delegated grants
        (default off); IncludeMicrosoftApps - report Microsoft first-party apps (default off).
        Switches default off because the alert form omits switches the user never touched.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $RiskRank = @{ Low = 1; Medium = 2; High = 3; Critical = 4 }
        $RankName = @{ 1 = 'Low'; 2 = 'Medium'; 3 = 'High'; 4 = 'Critical' }
        $IncludeDelegated = $true
        $ExcludeMicrosoftApps = $true
        $RateBy = 'Risk'
        $CategoryFilter = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $RiskRaw = $null
        if ($InputValue -is [string] -or $InputValue -is [System.ValueType]) {
            $RiskRaw = $InputValue
        } elseif ($InputValue -is [System.Collections.IDictionary] -or $InputValue -is [pscustomobject]) {
            $RiskRaw = $InputValue.MinimumRisk.value ?? $InputValue.MinimumRisk
            $RateByRaw = [string]($InputValue.RateBy.value ?? $InputValue.RateBy)
            if ($RateByRaw -in @('Impact', 'Suspicion')) { $RateBy = $RateByRaw }
            foreach ($Category in @($InputValue.Categories)) {
                $CategoryName = [string]($Category.value ?? $Category)
                if ($CategoryName) { [void]$CategoryFilter.Add($CategoryName) }
            }
            if ($InputValue.ExcludeDelegated -eq $true -or "$($InputValue.ExcludeDelegated)" -eq 'true') { $IncludeDelegated = $false }
            if ($InputValue.IncludeMicrosoftApps -eq $true -or "$($InputValue.IncludeMicrosoftApps)" -eq 'true') { $ExcludeMicrosoftApps = $false }
        }
        $MinRank = $RiskRank["$RiskRaw".Trim()]
        if (-not $MinRank) { $MinRank = $RiskRank['High'] }

        try {
            $Apps = @(Get-CIPPAppPermissionExposure -TenantFilter $TenantFilter -ExcludeDelegated:(-not $IncludeDelegated) -SkipSignInActivity)
        } catch [System.Management.Automation.ItemNotFoundException] {
            # A cache has not been collected for this tenant yet: nothing can be checked.
            return
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        $RowKeys = [System.Collections.Generic.List[string]]::new()

        foreach ($App in $Apps) {
            if ($App.IsCippApp) { continue }
            if ($ExcludeMicrosoftApps -and $App.IsMicrosoftApp) { continue }
            $AppRiskRank = [int]$RiskRank[[string]$App.Risk]
            if ($RateBy -eq 'Risk' -and $AppRiskRank -lt $MinRank) { continue }

            $Kept = [System.Collections.Generic.List[object]]::new()
            foreach ($D in $App.PermissionDetails) {
                if ($RateBy -ne 'Risk') {
                    $Rank = $RiskRank[[string]$D.$RateBy]
                    if (-not $Rank -or $Rank -lt $MinRank) { continue }
                }
                if ($CategoryFilter.Count -gt 0) {
                    $CategoryMatch = $false
                    foreach ($Category in $D.Categories) {
                        if ($CategoryFilter.Contains([string]$Category)) { $CategoryMatch = $true; break }
                    }
                    if (-not $CategoryMatch) { continue }
                }
                $Kept.Add($D)
            }
            if ($Kept.Count -eq 0) { continue }

            $Details = $Kept.ToArray()
            $DetailKeys = [string[]]::new($Details.Count)
            $MaxSuspicion = 0
            $MaxImpact = 0
            for ($i = 0; $i -lt $Details.Count; $i++) {
                $D = $Details[$i]
                $DetailKeys[$i] = '{0}|{1}|{2}|{3}|{4}' -f (5 - $RiskRank[[string]$D.Impact]), (5 - $RiskRank[[string]$D.Suspicion]), $D.Api, $D.Type, $D.Name
                $MaxSuspicion = [Math]::Max($MaxSuspicion, [int]$RiskRank[[string]$D.Suspicion])
                $MaxImpact = [Math]::Max($MaxImpact, [int]$RiskRank[[string]$D.Impact])
            }
            # Explicit type arguments: without them PowerShell sorts a copy of the items array.
            [Array]::Sort[string, object]($DetailKeys, $Details, [System.StringComparer]::OrdinalIgnoreCase)

            $Labels = [string[]]::new($Details.Count)
            for ($i = 0; $i -lt $Details.Count; $i++) {
                $D = $Details[$i]
                $Labels[$i] = if ($D.ConsentType) {
                    '{0}: {1} ({2}, suspicion {3}, impact {4}, {5})' -f $D.Api, $D.Name, $D.Type, $D.Suspicion, $D.Impact, $D.ConsentType
                } else {
                    '{0}: {1} ({2}, suspicion {3}, impact {4})' -f $D.Api, $D.Name, $D.Type, $D.Suspicion, $D.Impact
                }
            }
            $PermissionText = $Labels -join '; '
            $SortRank = switch ($RateBy) { 'Impact' { $MaxImpact } 'Suspicion' { $MaxSuspicion } default { $AppRiskRank } }
            $DisplayName = $App.AppDisplayName

            $Rows.Add([PSCustomObject]@{
                    Message            = "App '$DisplayName' ($($App.AppId)) is rated $($App.Risk) risk and holds: $PermissionText"
                    AppDisplayName     = $DisplayName
                    AppId              = $App.AppId
                    ServicePrincipalId = $App.ServicePrincipalId
                    Risk               = $App.Risk
                    RiskReasons        = $App.RiskReasons
                    Ownership          = $App.Ownership
                    Vendor             = $App.Vendor
                    VendorCategory     = $App.VendorCategory
                    PublisherName      = $App.PublisherName
                    VerifiedPublisher  = $App.VerifiedPublisher
                    IsMicrosoftApp     = $App.IsMicrosoftApp
                    AccountEnabled     = $App.AccountEnabled
                    HighestImpact      = $RankName[$MaxImpact]
                    HighestSuspicion   = $RankName[$MaxSuspicion]
                    PermissionCount    = $Details.Count
                    Permissions        = $PermissionText
                    PermissionDetails  = $Details
                    Tenant             = $TenantFilter
                })
            $RowKeys.Add(('{0}|{1}|{2}' -f (5 - $SortRank), $DisplayName, $App.ServicePrincipalId))
        }

        $AlertData = $Rows.ToArray()
        [Array]::Sort[string, object]($RowKeys.ToArray(), $AlertData, [System.StringComparer]::OrdinalIgnoreCase)
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not check risky app permissions for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}

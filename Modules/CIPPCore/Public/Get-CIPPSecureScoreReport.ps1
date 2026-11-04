function Get-CIPPSecureScoreReport {
    <#
    .SYNOPSIS
        Generates a Secure Score summary from the CIPP Reporting database

    .DESCRIPTION
        Returns the latest Secure Score per tenant from the nightly cache, with no live Graph calls.

        Reads the compact SecureScoreSummary rows (one per tenant, written by Set-CIPPDBCacheSecureScore).
        Tenants without a summary row yet fall back to the full SecureScore records as described below,
        per tenant, so a partially refreshed cache never drops a tenant from the report.

        Each cached SecureScore record carries the full controlScores breakdown, averageComparativeScores
        and enabledServices — roughly 15 KB per record, and the cache keeps 14 days per tenant. Reading
        those in full to report a single percentage costs megabytes across an estate, so this function
        projects to currentScore / maxScore / createdDateTime at parse time. CippJson skips every other
        field without materializing it, which is the only real memory lever available here.

        Use -IncludeHistory to also return the retained daily scores as a compact trend. This costs
        nothing extra: the daily records must be read anyway to find the most recent one, and the
        projection keeps each point to three fields.

    .PARAMETER TenantFilter
        The tenant to report on, or 'AllTenants' for every tenant.

    .PARAMETER IncludeHistory
        Include the retained per-day scores for each tenant as a History array.

    .PARAMETER IncludeControls
        Return @{ Results; Catalog } instead of the plain rows: each tenant carries its per-control
        scores and states as Controls, and Catalog holds the shared control metadata keyed by control name.

    .EXAMPLE
        Get-CIPPSecureScoreReport -TenantFilter 'AllTenants'

    .EXAMPLE
        Get-CIPPSecureScoreReport -TenantFilter 'contoso.onmicrosoft.com' -IncludeHistory
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeHistory,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeControls
    )

    # Builds the same per-tenant rows as the legacy path from the compact summary rows. With
    # -IncludeControls the tenant-invariant control metadata (title, tier, ...) goes into one shared
    # Catalog keyed by control name instead of repeating on every tenant.
    function Get-SecureScoreFromSummary {
        param($Rows, $TenantLookup, [switch]$IncludeHistory, [switch]$IncludeControls)

        $Projection = if ($IncludeControls) { $null } else { [string[]]@('currentScore', 'maxScore', 'createdDateTime', 'history') }
        $CatalogFields = 'title', 'controlCategory', 'tier', 'maxScore', 'userImpact', 'implementationCost', 'threats'
        $Catalog = @{}

        $Results = foreach ($Row in $Rows) {
            if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }
            try {
                $Summary = @([CIPP.CippJson]::ConvertFromJson($Row.Data, $Projection))[0]
            } catch {
                Write-Information "Skipping unparseable SecureScoreSummary row for '$($Row.PartitionKey)': $($_.Exception.Message)"
                continue
            }
            if ($null -eq $Summary) { continue }

            $Current = [double]($Summary.currentScore ?? 0)
            $Max = [double]($Summary.maxScore ?? 0)
            $TenantInfo = $TenantLookup[[string]$Row.PartitionKey]

            $Output = [PSCustomObject]@{
                Tenant          = $Row.PartitionKey
                TenantId        = $TenantInfo.customerId ?? ''
                TenantName      = $TenantInfo.displayName ?? $Row.PartitionKey
                CurrentScore    = [math]::Round($Current, 2)
                MaxScore        = $Max
                PercentageScore = if ($Max -gt 0) { [math]::Round(($Current / $Max) * 100, 2) } else { 0 }
                CapturedAt      = $Summary.createdDateTime
            }

            if ($IncludeHistory) {
                $Output | Add-Member -NotePropertyName 'History' -NotePropertyValue @(
                    foreach ($Point in @($Summary.history)) {
                        $PointMax = [double]($Point.maxScore ?? 0)
                        [PSCustomObject]@{
                            Date            = $Point.date
                            CurrentScore    = [math]::Round([double]($Point.currentScore ?? 0), 2)
                            PercentageScore = if ($PointMax -gt 0) { [math]::Round(([double]($Point.currentScore ?? 0) / $PointMax) * 100, 2) } else { 0 }
                        }
                    }
                ) -Force
            }

            if ($IncludeControls) {
                $Output | Add-Member -NotePropertyName 'Controls' -NotePropertyValue @(
                    foreach ($Control in @($Summary.controls)) {
                        $Name = [string]$Control.controlName
                        if (-not $Name) { continue }
                        if (-not $Catalog.ContainsKey($Name)) {
                            $Entry = [ordered]@{}
                            foreach ($Field in $CatalogFields) { $Entry[$Field] = $Control.$Field }
                            $Catalog[$Name] = $Entry
                        }
                        # Most controls never had a state change; leaving the empty state fields out
                        # keeps the estate-wide payload to roughly half (the frontend defaults them).
                        $Slim = [ordered]@{
                            controlName       = $Name
                            score             = $Control.score
                            scoreInPercentage = $Control.scoreInPercentage
                        }
                        if ($Control.state -and $Control.state -ne 'Default') { $Slim.state = $Control.state }
                        foreach ($Field in 'stateBy', 'stateDate', 'stateComment') {
                            if ($Control.$Field) { $Slim[$Field] = $Control.$Field }
                        }
                        [PSCustomObject]$Slim
                    }
                ) -Force
            }

            $Output
        }

        [PSCustomObject]@{ Results = @($Results); Catalog = $Catalog }
    }

    # Per-tenant rows from the full daily SecureScore records (~15 KB each), for tenants that have no
    # summary row yet. Only the score fields are parsed; controlScores and friends are skipped.
    function Get-SecureScoreFromRecords {
        param($Rows, $TenantLookup, [switch]$IncludeHistory)

        $Projection = [string[]]@('currentScore', 'maxScore', 'createdDateTime')

        $ByTenant = @{}
        foreach ($Row in $Rows) {
            if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }
            try {
                $Parsed = [CIPP.CippJson]::ConvertFromJson($Row.Data, $Projection)
            } catch {
                Write-Information "Skipping unparseable SecureScore row for '$($Row.PartitionKey)': $($_.Exception.Message)"
                continue
            }

            foreach ($Record in @($Parsed)) {
                if ($null -eq $Record) { continue }
                $Key = $Row.PartitionKey
                if (-not $ByTenant.ContainsKey($Key)) {
                    $ByTenant[$Key] = [System.Collections.Generic.List[object]]::new()
                }
                [void]$ByTenant[$Key].Add($Record)
            }
        }

        $Results = foreach ($Key in $ByTenant.Keys) {
            $Points = @($ByTenant[$Key] | Sort-Object -Property { [datetime]($_.createdDateTime) } -Descending)
            $Latest = $Points | Select-Object -First 1
            if (-not $Latest) { continue }

            $Current = [double]($Latest.currentScore ?? 0)
            $Max = [double]($Latest.maxScore ?? 0)
            $TenantInfo = $TenantLookup[$Key]

            $Output = [PSCustomObject]@{
                Tenant          = $Key
                TenantId        = $TenantInfo.customerId ?? ''
                TenantName      = $TenantInfo.displayName ?? $Key
                CurrentScore    = [math]::Round($Current, 2)
                MaxScore        = $Max
                PercentageScore = if ($Max -gt 0) { [math]::Round(($Current / $Max) * 100, 2) } else { 0 }
                CapturedAt      = $Latest.createdDateTime
            }

            if ($IncludeHistory) {
                $Output | Add-Member -NotePropertyName 'History' -NotePropertyValue @(
                    $Points | Sort-Object -Property { [datetime]($_.createdDateTime) } | ForEach-Object {
                        $PointMax = [double]($_.maxScore ?? 0)
                        [PSCustomObject]@{
                            Date            = $_.createdDateTime
                            CurrentScore    = [math]::Round([double]($_.currentScore ?? 0), 2)
                            PercentageScore = if ($PointMax -gt 0) {
                                [math]::Round(([double]($_.currentScore ?? 0) / $PointMax) * 100, 2)
                            } else { 0 }
                        }
                    }
                ) -Force
            }

            $Output
        }

        @($Results)
    }

    try {
        $IsAllTenants = $TenantFilter -eq 'AllTenants'
        $Partition = 'allTenants'
        if (-not $IsAllTenants) {
            $Partition = (Get-Tenants -TenantFilter $TenantFilter).defaultDomainName
            if (-not $Partition) { throw "Tenant '$TenantFilter' not found" }
        }

        $TenantLookup = @{}
        foreach ($KnownTenant in (Get-Tenants -IncludeErrors)) {
            if ($KnownTenant.defaultDomainName) {
                $TenantLookup[$KnownTenant.defaultDomainName] = $KnownTenant
            }
        }

        # Drop the '<Type>-Count' bookkeeping row (no Data) and partitions for tenants we no longer
        # manage. The allTenants read is deliberately unfiltered and cached rows outlive an excluded
        # tenant, so without this they keep showing up in the estate-wide view.
        $ManagedRows = {
            param($Rows, $Type)
            @($Rows | Where-Object { $_.RowKey -ne "$Type-Count" -and $TenantLookup.ContainsKey([string]$_.PartitionKey) })
        }

        # Fast path: one compact SecureScoreSummary row per tenant, written by the nightly SecureScore
        # cache job. Tenants without one (cache job not run since the update, or their profile fetch
        # failed) are read from the full daily SecureScore records instead, so they never drop out.
        $SummaryRows = & $ManagedRows (Get-CIPPDbItem -TenantFilter $Partition -Type 'SecureScoreSummary') 'SecureScoreSummary'
        $Summary = Get-SecureScoreFromSummary -Rows $SummaryRows -TenantLookup $TenantLookup -IncludeHistory:$IncludeHistory -IncludeControls:$IncludeControls

        $LegacyRows = if ($SummaryRows.Count -eq 0) {
            # Nothing summarised yet: one read for the whole scope, as before.
            & $ManagedRows (Get-CIPPDbItem -TenantFilter $Partition -Type 'SecureScore') 'SecureScore'
        } else {
            $Covered = [System.Collections.Generic.HashSet[string]]::new([string[]]@($SummaryRows.PartitionKey), [StringComparer]::OrdinalIgnoreCase)
            $Scope = if ($IsAllTenants) { @($TenantLookup.Keys) } else { @($Partition) }
            foreach ($Missing in $Scope) {
                if ($Covered.Contains($Missing)) { continue }
                & $ManagedRows (Get-CIPPDbItem -TenantFilter $Missing -Partition $Missing -Type 'SecureScore') 'SecureScore'
            }
        }
        $Legacy = Get-SecureScoreFromRecords -Rows @($LegacyRows) -TenantLookup $TenantLookup -IncludeHistory:$IncludeHistory

        $Results = @(@($Summary.Results) + @($Legacy) | Sort-Object -Property PercentageScore)
        # Legacy tenants carry no Controls; the controls views fill in once their summary row exists.
        return $IncludeControls ? [PSCustomObject]@{ Results = $Results; Catalog = $Summary.Catalog } : $Results
    } catch {
        Write-LogMessage -API 'SecureScoreReport' -tenant $TenantFilter -message "Failed to build secure score report: $($_.Exception.Message)" -sev Error
        throw
    }
}

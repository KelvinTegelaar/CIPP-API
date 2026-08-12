function Get-CIPPSecureScoreReport {
    <#
    .SYNOPSIS
        Generates a Secure Score summary from the CIPP Reporting database

    .DESCRIPTION
        Returns the latest Secure Score per tenant from the nightly cache, with no live Graph calls.

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
        [switch]$IncludeHistory
    )

    try {
        $IsAllTenants = $TenantFilter -eq 'AllTenants'

        if ($IsAllTenants) {
            $Rows = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'SecureScore'
        } else {
            $Tenant = (Get-Tenants -TenantFilter $TenantFilter).defaultDomainName
            if (-not $Tenant) { throw "Tenant '$TenantFilter' not found" }
            $Rows = Get-CIPPDbItem -TenantFilter $Tenant -Type 'SecureScore'
        }

        # The type prefix filter also matches the '<Type>-Count' bookkeeping row, which carries no Data.
        $Rows = @($Rows | Where-Object { $_.RowKey -ne 'SecureScore-Count' })
        if ($Rows.Count -eq 0) { return @() }

        $TenantLookup = @{}
        foreach ($KnownTenant in (Get-Tenants -IncludeErrors)) {
            if ($KnownTenant.defaultDomainName) {
                $TenantLookup[$KnownTenant.defaultDomainName] = $KnownTenant
            }
        }

        # Drop partitions for tenants we no longer manage. The allTenants read is deliberately
        # unfiltered and cached rows outlive an excluded tenant, so without this they keep showing
        # up in the estate-wide view. Every other AllTenants report filters the same way.
        $Rows = @($Rows | Where-Object { $TenantLookup.ContainsKey([string]$_.PartitionKey) })
        if ($Rows.Count -eq 0) { return @() }

        # Only these three fields are ever materialized; controlScores and friends are skipped by the parser.
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
                PercentageScore = if ($Max -gt 0) { [math]::Round(($Current / $Max) * 100, 1) } else { 0 }
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
                                [math]::Round(([double]($_.currentScore ?? 0) / $PointMax) * 100, 1)
                            } else { 0 }
                        }
                    }
                ) -Force
            }

            $Output
        }

        return @($Results | Sort-Object -Property PercentageScore)
    } catch {
        Write-LogMessage -API 'SecureScoreReport' -tenant $TenantFilter -message "Failed to build secure score report: $($_.Exception.Message)" -sev Error
        throw
    }
}

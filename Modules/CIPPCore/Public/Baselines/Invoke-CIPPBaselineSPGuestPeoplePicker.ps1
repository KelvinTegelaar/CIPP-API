function Invoke-CIPPBaselineSPGuestPeoplePicker {
    <#
    .SYNOPSIS
        SPGuestPeoplePicker executor: applies People Picker guest visibility to the tenant default
        and each offending site collection, once per 24h per tenant.
    .DESCRIPTION
        Each target from the prepare hook carries a Scope ('tenant' or 'site') and the value in
        'Wanted'. Tenant targets write through Set-CIPPSPOTenant, site targets through the concurrent
        Set-CIPPSPOSiteBulk fan-out. It does NOT re-read after writing: the eventually-consistent site
        enumeration lags a just-applied write, and the baseline engine already verifies optimistically
        on the next daily cache read.

        A 24h rerun guard (Test-CIPPRerun, shared with the classic standard via the 'SPGuestPeoplePicker'
        key) gates the write sweep: the prepare's offender set is derived from the SPOSites cache, which
        only refreshes daily, so without the guard a sub-daily baseline schedule would re-issue the same
        writes against a stale picture and throttle SharePoint. Detection and drift reporting are not
        gated - only the sweep.

        Partial failure does NOT throw - sites that wrote stay written, failures are logged, and once
        the cache reflects the successes the next run's prepare re-derives only the still-drifted set.
        A run where every write failed throws (a permission/endpoint problem, not drift).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Targets = @($Current.targets | Where-Object { $_ })
    if ($Targets.Count -eq 0) { return }

    # Once-per-24h per tenant. Test-CIPPRerun records the run as it allows it, and the classic standard
    # shares this key, so whichever system sweeps first blocks the other until the next daily cache run
    # reflects the change. Only reached when there is drift to write (the engine calls the executor only
    # for a non-compliant, remediate-enabled item), so detection/alerting are never gated by it.
    if (Test-CIPPRerun -Tenant $TenantFilter -API 'SPGuestPeoplePicker' -Interval 86400) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'SPGuestPeoplePicker: write sweep already ran within the last 24h - skipping it until the next daily cache run re-evaluates the result.' -Sev 'Info'
        return
    }

    $AuthSplat = @{}
    if ($Remediate.useCertificate) { $AuthSplat['UseCertificate'] = $true }
    $Property = 'ShowPeoplePickerSuggestionsForGuestUsers'

    $Attempted = 0
    $Failed = 0
    $FailureDetail = [System.Collections.Generic.List[string]]::new()

    # Tenant default (at most one target): a fresh Get-CIPPSPOTenant supplies the write handle, then
    # one Set-CIPPSPOTenant. No re-read - the next daily cache run confirms it.
    foreach ($Target in @($Targets | Where-Object { $_.Scope -eq 'tenant' })) {
        $Attempted++
        try {
            $SPOTenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter @AuthSplat | Select-Object -First 1
            if (-not $SPOTenant) { throw "Could not resolve the SharePoint tenant object for $TenantFilter." }
            $null = $SPOTenant | Set-CIPPSPOTenant -Properties @{ $Property = [bool]$Target.Wanted } @AuthSplat
        } catch {
            $Failed++
            $FailureDetail.Add("Tenant default -> $($_.Exception.Message)")
        }
    }

    # Existing sites: one concurrent bulk write. Per-site success/failure comes straight from the bulk
    # result (CSOM reports per-site errors in the response body); no separate verification read.
    $SiteTargets = @($Targets | Where-Object { $_.Scope -eq 'site' -and $_.SiteUrl })
    if ($SiteTargets.Count -gt 0) {
        $BulkSites = @($SiteTargets | ForEach-Object { @{ SiteUrl = $_.SiteUrl; Properties = @{ $Property = [bool]$_.Wanted } } })
        try {
            $Results = @(Set-CIPPSPOSiteBulk -TenantFilter $TenantFilter -Sites $BulkSites @AuthSplat)
            $ResultByUrl = @{}
            foreach ($Result in $Results) { $ResultByUrl["$($Result.SiteUrl)"] = $Result }
            foreach ($SiteTarget in $SiteTargets) {
                $Attempted++
                $Result = $ResultByUrl["$($SiteTarget.SiteUrl)"]
                if (-not $Result -or -not $Result.Success) {
                    $Failed++
                    $FailureDetail.Add("$($SiteTarget.SiteUrl) -> $(if ($Result.Error) { $Result.Error } else { 'no result returned' })")
                }
            }
        } catch {
            foreach ($SiteTarget in $SiteTargets) { $Attempted++; $Failed++ }
            $FailureDetail.Add("Site batch -> $($_.Exception.Message)")
        }
    }

    if ($FailureDetail.Count -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Guest People Picker: $Failed of $Attempted writes failed. $($FailureDetail -join ' | ')" -Sev 'Warning'
    }
    if ($Attempted -gt 0 -and $Failed -eq $Attempted) {
        throw "SPGuestPeoplePicker: all $Attempted writes failed. $($FailureDetail | Select-Object -First 1)"
    }
}

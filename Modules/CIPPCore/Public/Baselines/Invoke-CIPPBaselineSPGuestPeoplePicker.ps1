function Invoke-CIPPBaselineSPGuestPeoplePicker {
    <#
    .SYNOPSIS
        SPGuestPeoplePicker executor: applies People Picker guest visibility to the tenant default
        and each offending site collection, then re-reads authoritatively to verify.
    .DESCRIPTION
        Each target from the prepare hook carries a Scope ('tenant' or 'site') and the value in
        'Wanted'. Tenant targets write through Set-CIPPSPOTenant, site targets through the concurrent
        Set-CIPPSPOSiteBulk fan-out. After writing, every changed object is re-read AUTHORITATIVELY
        (Get-CIPPSPOTenant / Get-CIPPSPOSiteBulk single-site, never the eventually-consistent site
        enumeration) so a write that reported success but did not stick is caught, not assumed.

        Partial failure does NOT throw - fixed objects stay fixed, failures are logged, and the next
        run's live prepare re-derives the offender set and retries. A run where every write failed
        throws (a permission/endpoint problem, not drift).
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

    $AuthSplat = @{}
    if ($Remediate.useCertificate) { $AuthSplat['UseCertificate'] = $true }
    $Property = 'ShowPeoplePickerSuggestionsForGuestUsers'

    $Attempted = 0
    $Failed = 0
    $FailureDetail = [System.Collections.Generic.List[string]]::new()

    # Tenant default (at most one target): write, then authoritatively re-read to verify.
    foreach ($Target in @($Targets | Where-Object { $_.Scope -eq 'tenant' })) {
        $Attempted++
        try {
            $SPOTenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter @AuthSplat
            if (-not $SPOTenant) { throw "Could not resolve the SharePoint tenant object for $TenantFilter." }
            $null = $SPOTenant | Set-CIPPSPOTenant -Properties @{ $Property = [bool]$Target.Wanted } @AuthSplat
            $After = [bool](Get-CIPPSPOTenant -TenantFilter $TenantFilter @AuthSplat).ShowPeoplePickerSuggestionsForGuestUsers
            if ($After -ne [bool]$Target.Wanted) { $Failed++; $FailureDetail.Add('Tenant default -> value did not change after write') }
        } catch {
            $Failed++
            $FailureDetail.Add("Tenant default -> $($_.Exception.Message)")
        }
    }

    # Existing sites: one concurrent bulk write, then an authoritative single-site re-read of only
    # the sites we changed (bounded by the offender count).
    $SiteTargets = @($Targets | Where-Object { $_.Scope -eq 'site' -and $_.SiteUrl })
    if ($SiteTargets.Count -gt 0) {
        $BulkSites = @($SiteTargets | ForEach-Object { @{ SiteUrl = $_.SiteUrl; Properties = @{ $Property = [bool]$_.Wanted } } })
        $WriteOk = $true
        try { $null = Set-CIPPSPOSiteBulk -TenantFilter $TenantFilter -Sites $BulkSites @AuthSplat } catch {
            $WriteOk = $false
            $FailureDetail.Add("Site batch -> $($_.Exception.Message)")
        }

        if (-not $WriteOk) {
            foreach ($SiteTarget in $SiteTargets) { $Attempted++; $Failed++ }
        } else {
            $WantedByUrl = @{}
            foreach ($SiteTarget in $SiteTargets) { $WantedByUrl["$($SiteTarget.SiteUrl)"] = [bool]$SiteTarget.Wanted }
            $Verified = @(Get-CIPPSPOSiteBulk -TenantFilter $TenantFilter -SiteUrls @($SiteTargets.SiteUrl) @AuthSplat)
            foreach ($Result in $Verified) {
                $Attempted++
                if (-not $Result.Success -or [bool]$Result.Site.ShowPeoplePickerSuggestionsForGuestUsers -ne $WantedByUrl["$($Result.SiteUrl)"]) {
                    $Failed++
                    $FailureDetail.Add("$($Result.SiteUrl) -> $(if ($Result.Error) { $Result.Error } else { 'value did not change after write' })")
                }
            }
        }
    }

    if ($FailureDetail.Count -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Guest People Picker: $Failed of $Attempted writes unverified/failed. $($FailureDetail -join ' | ')" -Sev 'Warning'
    }
    if ($Failed -eq $Attempted) {
        throw "SPGuestPeoplePicker: all $Attempted writes failed. $($FailureDetail | Select-Object -First 1)"
    }
}

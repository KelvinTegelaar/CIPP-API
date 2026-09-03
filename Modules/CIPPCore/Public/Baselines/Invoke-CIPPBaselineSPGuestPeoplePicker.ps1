function Invoke-CIPPBaselineSPGuestPeoplePicker {
    <#
    .SYNOPSIS
        SPGuestPeoplePicker executor: applies People Picker guest visibility to the tenant default
        and each offending site collection.
    .DESCRIPTION
        Each target from the prepare hook carries a Scope ('tenant' or 'site') and the value in
        'Wanted'. Tenant targets write through Set-CIPPSPOTenant (a fresh identity is read first,
        since the CSOM ObjectIdentity is connection-scoped), site targets through Set-CIPPSPOSite.
        CSOM has no batch, so writes are sequential.

        Partial failure does NOT throw - fixed objects stay fixed, failures are logged, and the next
        run retries the remainder. A run where every write failed throws (a permission/endpoint
        problem, not drift). refreshCache re-collects afterwards so fixed objects do not read back as
        drift next run.
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

    foreach ($Target in $Targets) {
        $Attempted++
        try {
            if ($Target.Scope -eq 'tenant') {
                $SPOTenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter @AuthSplat
                if (-not $SPOTenant) { throw "Could not resolve the SharePoint tenant object for $TenantFilter." }
                $null = $SPOTenant | Set-CIPPSPOTenant -Properties @{ $Property = [bool]$Target.Wanted } @AuthSplat
            } else {
                $Response = Set-CIPPSPOSite -TenantFilter $TenantFilter -SiteUrl $Target.SiteUrl -Properties @{ $Property = [bool]$Target.Wanted } @AuthSplat
                $CsomError = ($Response | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
                if ($CsomError) { throw $CsomError }
            }
        } catch {
            $Failed++
            $FailureDetail.Add("$($Target.SiteUrl ?? 'Tenant default') -> $($_.Exception.Message)")
        }
    }

    if ($FailureDetail.Count -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Guest People Picker: $Failed of $Attempted writes failed. $($FailureDetail -join ' | ')" -Sev 'Warning'
    }
    if ($Failed -eq $Attempted) {
        throw "SPGuestPeoplePicker: all $Attempted writes failed. $($FailureDetail | Select-Object -First 1)"
    }

    foreach ($CacheType in @($Remediate.refreshCache | Where-Object { $_ })) {
        $Collector = Get-Command -Name "Set-CIPPDBCache$CacheType" -ErrorAction SilentlyContinue
        if (-not $Collector) { continue }
        try { $null = & $Collector -TenantFilter $TenantFilter } catch {
            Write-Information "Baselines: cache refresh for $CacheType on $TenantFilter after the People Picker run failed: $($_.Exception.Message)"
        }
    }
}

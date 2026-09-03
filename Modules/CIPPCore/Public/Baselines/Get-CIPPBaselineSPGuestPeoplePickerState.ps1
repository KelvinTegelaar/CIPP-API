function Get-CIPPBaselineSPGuestPeoplePickerState {
    <#
    .SYNOPSIS
        Prepare hook for SPGuestPeoplePicker: the tenant default and every site collection whose
        People Picker guest visibility differs from the wanted state.
    .DESCRIPTION
        Reads only the reporting caches - the tenant default from SPOTenant (the definition's primary
        read.cacheType, so the engine collects it on miss with certificate auth) and per-site values
        from the generic SPOSites cache. No live calls. A missing SPOTenant cache returns null so the
        engine collects it. The tenant default and existing sites are set independently, so this one
        standard covers both.

        Returns the offenders/targets pair the sweep model expects: offenders are display strings
        graded against [] ('Tenant default' plus offending site URLs); targets carry the Scope and
        the value to write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Wanted = ($Item.Variables.showGuests -eq $true) -or ("$($Item.Variables.showGuests)" -eq 'true')

    # Primary cache: engine collects SPOTenant on miss (with cert via read.collectorArgs).
    $Tenant = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SPOTenant' | Select-Object -First 1
    if (-not $Tenant) { return @{ Current = $null } }

    $Offenders = [System.Collections.Generic.List[string]]::new()
    $Targets = [System.Collections.Generic.List[object]]::new()

    if ([bool]$Tenant.ShowPeoplePickerSuggestionsForGuestUsers -ne $Wanted) {
        $Offenders.Add('Tenant default')
        $Targets.Add([PSCustomObject]@{ Scope = 'tenant'; SiteUrl = $null; Wanted = $Wanted })
    }

    $Sites = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SPOSites' | Where-Object { $_ -and $_.Url })
    foreach ($Site in ($Sites | Where-Object { [bool]$_.ShowPeoplePickerSuggestionsForGuestUsers -ne $Wanted } | Sort-Object Url)) {
        $Offenders.Add("$($Site.Url)")
        $Targets.Add([PSCustomObject]@{ Scope = 'site'; SiteUrl = "$($Site.Url)"; Wanted = $Wanted })
    }

    @{ Current = [PSCustomObject]@{ offenders = @($Offenders); targets = @($Targets) } }
}

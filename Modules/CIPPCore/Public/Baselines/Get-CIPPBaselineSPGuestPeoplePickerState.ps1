function Get-CIPPBaselineSPGuestPeoplePickerState {
    <#
    .SYNOPSIS
        Prepare hook for SPGuestPeoplePicker: the tenant default and every site collection whose
        People Picker guest visibility differs from the wanted state.
    .DESCRIPTION
        Reads only the SPOSites cache (tenant + site rows). No live calls - a missing cache returns
        null so the engine collects it on miss via Set-CIPPDBCacheSPOSites. The tenant default and
        existing sites are set independently, so this one standard covers both.

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

    $Rows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SPOSites' | Where-Object { $_ })
    if ($Rows.Count -eq 0) { return @{ Current = $null } }

    $Offenders = [System.Collections.Generic.List[string]]::new()
    $Targets = [System.Collections.Generic.List[object]]::new()
    # Tenant first, then sites by URL, so the offenders list reads predictably.
    foreach ($Row in ($Rows | Sort-Object @{ e = { $_.Scope -ne 'tenant' } }, Url)) {
        if ([bool]$Row.ShowPeoplePickerSuggestionsForGuestUsers -eq $Wanted) { continue }
        if ($Row.Scope -eq 'tenant') {
            $Offenders.Add('Tenant default')
            $Targets.Add([PSCustomObject]@{ Scope = 'tenant'; SiteUrl = $null; Wanted = $Wanted })
        } else {
            $Offenders.Add("$($Row.Url)")
            $Targets.Add([PSCustomObject]@{ Scope = 'site'; SiteUrl = "$($Row.Url)"; Wanted = $Wanted })
        }
    }

    @{ Current = [PSCustomObject]@{ offenders = @($Offenders); targets = @($Targets) } }
}

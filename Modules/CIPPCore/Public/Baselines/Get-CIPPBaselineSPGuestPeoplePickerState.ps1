function Get-CIPPBaselineSPGuestPeoplePickerState {
    <#
    .SYNOPSIS
        Prepare hook for SPGuestPeoplePicker: the tenant default and every site collection whose
        People Picker guest visibility differs from the wanted state.
    .DESCRIPTION
        Reads LIVE from SharePoint (not the reporting cache), so a remediating standard never acts on
        stale data: the tenant default via an authoritative Get-CIPPSPOTenant and every site via the
        Get-CIPPSPOSite enumeration (fresher than the nightly SPOSites cache). SharePoint app-only
        requires the SAM certificate. The tenant default and existing sites are set independently, so
        this one standard covers both.

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

    $Tenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter -UseCertificate | Select-Object -First 1
    if (-not $Tenant) { return @{ Current = $null; NoDataReason = 'Could not read the SharePoint tenant configuration.' } }
    $Sites = @(Get-CIPPSPOSite -TenantFilter $TenantFilter -UseCertificate | Where-Object { $_ -and $_.Url })

    $Offenders = [System.Collections.Generic.List[string]]::new()
    $Targets = [System.Collections.Generic.List[object]]::new()

    if ([bool]$Tenant.ShowPeoplePickerSuggestionsForGuestUsers -ne $Wanted) {
        $Offenders.Add('Tenant default')
        $Targets.Add([PSCustomObject]@{ Scope = 'tenant'; SiteUrl = $null; Wanted = $Wanted })
    }

    foreach ($Site in ($Sites | Where-Object { [bool]$_.ShowPeoplePickerSuggestionsForGuestUsers -ne $Wanted } | Sort-Object Url)) {
        $Offenders.Add("$($Site.Url)")
        $Targets.Add([PSCustomObject]@{ Scope = 'site'; SiteUrl = "$($Site.Url)"; Wanted = $Wanted })
    }

    @{ Current = [PSCustomObject]@{ offenders = @($Offenders); targets = @($Targets) } }
}

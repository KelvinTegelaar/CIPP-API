function Get-CIPPBaselineSPGuestPeoplePickerState {
    <#
    .SYNOPSIS
        Prepare hook for SPGuestPeoplePicker: the tenant default and every cached site collection whose
        People Picker guest visibility differs from the wanted state.
    .DESCRIPTION
        Decides offenders from cache, not the live enumeration. Which sites differ comes from the
        SPOSites reporting cache (refreshed by the daily SharePoint CIPPDB run); the tenant default is
        read through Get-CIPPSPOTenant's own 1h cache (which works app-only with the certificate even
        where the delegated SPOTenant reporting collector cannot). Reading cache keeps a large tenant
        from being enumerated live on every run and lets the baseline engine's optimistic post-write
        model verify on the next daily cache read.

        Detection always runs (the read is cheap and idempotent against the daily cache); the 24h
        rerun guard lives in the executor so it throttles only the write sweep, never drift reporting.

        Returns the offenders/targets pair the sweep model expects: offenders are display strings
        graded against [] ('Tenant default' plus offending site URLs); targets carry the Scope and the
        value to write. Current is $null (No Data) only when the tenant configuration cannot be read.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Wanted = ($Item.Variables.showGuests -eq $true) -or ("$($Item.Variables.showGuests)" -eq 'true')

    try {
        $Tenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter -UseCertificate | Select-Object -First 1
    } catch {
        return @{ Current = $null; NoDataReason = "Could not read the SharePoint tenant configuration: $($_.Exception.Message)" }
    }
    if (-not $Tenant) { return @{ Current = $null; NoDataReason = 'Could not read the SharePoint tenant configuration.' } }

    $Sites = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SPOSites' | Where-Object { $_ -and $_.Url })

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

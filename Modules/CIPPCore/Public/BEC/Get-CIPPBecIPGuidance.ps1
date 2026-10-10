function Get-CIPPBecIPGuidance {
    <#
    .SYNOPSIS
        Collects the address lists that tell the BEC investigation which IPs are known good or bad.
    .DESCRIPTION
        One entry per address or CIDR range: { Range, Prefix, Verdict (Trusted|Blocked), Strength
        (List|Hint), Source, Scope, Note }.
        - List (decides the verdict): CIPP's IP allow/block list for this tenant and AllTenants, where the
          most specific range wins and a tenant entry beats an AllTenants one (Resolve-CIPPIPAllowBlockList).
        - Hint (moves the score only): Conditional Access named locations marked trusted, and the
          Exchange tenant allow/block list and connection-filter IP lists. The Exchange lists describe
          sending mail servers rather than sign-ins, so they nudge rather than decide; hyphenated
          ranges in the connection filter are skipped.
        Each source degrades on its own: a failure is reported in the result's Error and the other
        sources still count.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER Anchor
        Anchor mailbox for the Exchange requests.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$Anchor
    )

    $Entries = [System.Collections.Generic.List[object]]::new()
    $Errors = [System.Collections.Generic.List[string]]::new()
    $AddEntry = {
        param($Value, $Verdict, $Strength, $Source, $Scope, $Note)
        $Range = try { ConvertTo-CIPPIPRange -Value ([string]$Value) } catch { $null }
        if (-not $Range) { return }
        $Prefix = if ($Range -match '/(\d+)$') { [int]$Matches[1] } elseif ($Range -match ':') { 128 } else { 32 }
        $Entries.Add([pscustomobject]@{ Range = $Range; Prefix = $Prefix; Verdict = $Verdict; Strength = $Strength; Source = $Source; Scope = $Scope; Note = [string]$Note })
    }

    try {
        foreach ($Entry in @(Get-CIPPIPAllowBlockList -TenantFilter $TenantFilter)) {
            & $AddEntry $Entry.Range $Entry.State 'List' $(if ($Entry.Scope -eq 'AllTenants') { 'CIPP IP list (all tenants)' } else { 'CIPP IP list (this tenant)' }) $Entry.Scope $Entry.Note
        }
    } catch {
        $Errors.Add("CIPP IP list: $($_.Exception.Message)")
    }

    try {
        $Locations = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter -AsApp $true)
        foreach ($Location in @($Locations | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.ipNamedLocation' -and $_.isTrusted -eq $true })) {
            foreach ($IpRange in @($Location.ipRanges)) { & $AddEntry $IpRange.cidrAddress 'Trusted' 'Hint' "Trusted named location '$($Location.displayName)'" 'Tenant' $null }
        }
    } catch {
        $Errors.Add("named locations: $((Get-NormalizedError -message $_.Exception.Message))")
    }

    try {
        foreach ($Item in @(Get-CIPPTenantAllowBlockListItems -TenantFilter $TenantFilter -ListType 'IP')) {
            $Verdict = if ([string]$Item.Action -eq 'Block') { 'Blocked' } else { 'Trusted' }
            & $AddEntry $Item.Value $Verdict 'Hint' "Tenant allow/block list ($($Item.Action))" 'Tenant' $Item.Notes
        }
    } catch {
        $Errors.Add("tenant allow/block list: $((Get-NormalizedError -message $_.Exception.Message))")
    }

    try {
        $ExoParams = @{ tenantid = $TenantFilter; cmdlet = 'Get-HostedConnectionFilterPolicy' }
        if ($Anchor) { $ExoParams.Anchor = $Anchor }
        foreach ($Policy in @(New-ExoRequest @ExoParams)) {
            foreach ($Value in @($Policy.IPAllowList)) { & $AddEntry $Value 'Trusted' 'Hint' "Connection filter allow list ($($Policy.Name))" 'Tenant' $null }
            foreach ($Value in @($Policy.IPBlockList)) { & $AddEntry $Value 'Blocked' 'Hint' "Connection filter block list ($($Policy.Name))" 'Tenant' $null }
        }
    } catch {
        $Errors.Add("connection filter: $((Get-NormalizedError -message $_.Exception.Message))")
    }

    $ErrorText = if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null }
    return New-CIPPBecCollectorResult -Data @($Entries) -Error $ErrorText
}

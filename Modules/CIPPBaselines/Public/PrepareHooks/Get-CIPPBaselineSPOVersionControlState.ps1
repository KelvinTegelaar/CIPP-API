function Get-CIPPBaselineSPOVersionControlState {
    <#
    .SYNOPSIS
        Prepare hook for SPOVersionControl: the SharePoint file version policy.
    .DESCRIPTION
        Auto-trim on grades one fact - the trim flag - because SharePoint manages the
        limits itself in that mode. Auto-trim off grades the flag plus the major version
        limit and expiry days.

        SharePoint accepts only 0 (never) or 30-36500 days for expiry; a configured value
        in the 1-29 gap reports No Data rather than grading a value the tenant would refuse
        to store - the classic's own validation gate.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $State = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'SPOTenant') | Select-Object -First 1
    if (-not $State) { return @{ Current = $null } }

    $AutoTrim = [bool]($Item.Variables.EnableAutoTrim -eq $true -or "$($Item.Variables.EnableAutoTrim)" -eq 'True')
    $MajorLimit = [int]"$($Item.Variables.MajorVersionLimit ?? 50)"
    $ExpireDays = [int]"$($Item.Variables.ExpireVersionsAfterDays ?? 0)"
    if (-not $AutoTrim -and $ExpireDays -ne 0 -and ($ExpireDays -lt 30 -or $ExpireDays -gt 36500)) { return @{ Current = $null } }

    if ($AutoTrim) {
        return @{
            Expected = [PSCustomObject]@{ autoExpirationVersionTrim = $true }
            Current  = [PSCustomObject]@{ autoExpirationVersionTrim = [bool]$State.EnableAutoExpirationVersionTrim }
        }
    }
    @{
        Expected = [PSCustomObject]@{
            autoExpirationVersionTrim = $false
            majorVersionLimit         = $MajorLimit
            expireVersionsAfterDays   = $ExpireDays
        }
        Current  = [PSCustomObject]@{
            autoExpirationVersionTrim = [bool]$State.EnableAutoExpirationVersionTrim
            majorVersionLimit         = [int]"$($State.MajorVersionLimit)"
            expireVersionsAfterDays   = [int]"$($State.ExpireVersionsAfterDays)"
        }
    }
}

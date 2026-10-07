function Get-CIPPBaselinesharingDomainRestrictionState {
    <#
    .SYNOPSIS
        Prepare hook for sharingDomainRestriction: SharePoint external sharing domain
        restrictions.
    .DESCRIPTION
        Mode 'none' grades the mode alone; allowList/blockList grade the mode plus the
        SORTED domain list on the matching side - the classic compared the sorted joined
        lists, so order never matters and the off-side list is not graded.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Settings = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'SharePointAdminSettings') | Select-Object -First 1
    if (-not $Settings) { return @{ Current = $null } }

    $Mode = "$($Item.Variables.Mode.value ?? $Item.Variables.Mode)"
    if ($Mode -notin @('none', 'allowList', 'blockList')) { return @{ Current = $null } }

    if ($Mode -eq 'none') {
        return @{
            Expected = [PSCustomObject]@{ sharingDomainRestrictionMode = 'none' }
            Current  = [PSCustomObject]@{ sharingDomainRestrictionMode = "$($Settings.sharingDomainRestrictionMode)" }
        }
    }

    $Domains = @("$($Item.Variables.Domains)".Split(',').Trim() | Where-Object { $_ } | Sort-Object)
    if ($Domains.Count -eq 0) { return @{ Current = $null } }
    $CurrentList = if ($Mode -eq 'allowList') { @($Settings.sharingAllowedDomainList) } else { @($Settings.sharingBlockedDomainList) }

    @{
        Expected = [PSCustomObject]@{
            sharingDomainRestrictionMode = $Mode
            restrictedDomains            = @($Domains)
        }
        Current  = [PSCustomObject]@{
            sharingDomainRestrictionMode = "$($Settings.sharingDomainRestrictionMode)"
            restrictedDomains            = @($CurrentList | Where-Object { $_ } | Sort-Object)
        }
    }
}

function Get-CIPPBaselineSPDirectSharingState {
    <#
    .SYNOPSIS
        Prepare hook for SPDirectSharing: the SharePoint default sharing link type.
    .DESCRIPTION
        Grades one fact: the tenant's default sharing link type is Direct (specific
        people). The SPO admin endpoint reports it as the string 'Direct' or the numeric 1
        depending on the API vintage; both grade compliant, exactly as the classic
        accepted both.
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

    @{
        Expected = [PSCustomObject]@{ defaultSharingLinkIsDirect = $true }
        Current  = [PSCustomObject]@{
            defaultSharingLinkIsDirect = [bool]("$($State.DefaultSharingLinkType)" -eq 'Direct' -or "$($State.DefaultSharingLinkType)" -eq '1')
        }
    }
}

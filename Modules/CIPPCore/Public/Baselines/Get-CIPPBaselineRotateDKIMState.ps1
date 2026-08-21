function Get-CIPPBaselineRotateDKIMState {
    <#
    .SYNOPSIS
        Prepare hook for RotateDKIM: enabled DKIM configs still on 1024-bit keys.
    .DESCRIPTION
        Grades the domains whose enabled DKIM signing still uses a 1024-bit selector key -
        the classic's exact selection. Disabled configs are not graded: rotating a disabled
        config does nothing, and AddDKIM owns enabling.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $DkimConfigs = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoDkimSigningConfig')
    if ($DkimConfigs.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoDkimSigningConfig')) {
        return @{ Current = $null }
    }

    $Weak = @($DkimConfigs | Where-Object {
            ($_.Selector1KeySize -eq 1024 -or $_.Selector2KeySize -eq 1024) -and $_.Enabled -eq $true
        })

    $Current = [PSCustomObject]@{ domainsWith1024BitDkim = @($Weak | ForEach-Object { "$($_.Identity)" } | Sort-Object) }

    @{
        Expected = [PSCustomObject]@{ domainsWith1024BitDkim = @() }
        Current  = $Current
    }
}

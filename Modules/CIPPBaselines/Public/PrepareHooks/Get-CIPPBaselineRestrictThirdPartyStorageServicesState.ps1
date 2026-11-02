function Get-CIPPBaselineRestrictThirdPartyStorageServicesState {
    <#
    .SYNOPSIS
        Prepare hook for RestrictThirdPartyStorageServices: the Microsoft 365 on the web
        service principal.
    .DESCRIPTION
        Grades one fact from the ServicePrincipals cache: the Microsoft 365 on the web
        service principal (appId c1f33bc0-bdb4-4248-ba9b-096807ddb43e) exists AND is
        disabled. A missing service principal means third-party storage is available (the
        platform default), so it grades unrestricted - the classic's exact semantics.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $ServicePrincipals = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ServicePrincipals')
    if ($ServicePrincipals.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ServicePrincipals')) {
        return @{ Current = $null }
    }
    $Principal = @($ServicePrincipals | Where-Object { "$($_.appId)" -eq 'c1f33bc0-bdb4-4248-ba9b-096807ddb43e' }) | Select-Object -First 1

    @{
        Expected = [PSCustomObject]@{ thirdPartyStorageRestricted = $true }
        Current  = [PSCustomObject]@{ thirdPartyStorageRestricted = [bool]($null -ne $Principal -and $Principal.accountEnabled -eq $false) }
    }
}

function Get-CIPPLicenseCatalog {
    <#
    .SYNOPSIS
        Load the shipped license catalog (Config\LicenseCatalog.json).

    .DESCRIPTION
        The catalog carries, for every SKU the optimization report can reason about:
        - prices   : public per-user/month list price per ISO currency (annual commitment)
        - family   : the product ladder it belongs to (business, enterprise, frontline, ...)
        - tier     : its position in that ladder
        - eligibleTarget : whether it may be recommended to users outside its own family

        plus the capability map (plain-language feature -> Microsoft service plan ids) and the
        family definitions. Parsed once per process and cached in script scope.

    .PARAMETER Force
        Re-read the file even when a parsed copy is cached.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if ($script:CIPPLicenseCatalog -and -not $Force) { return $script:CIPPLicenseCatalog }

    $Path = Join-Path $env:CIPPRootPath 'Config\LicenseCatalog.json'
    if (-not (Test-Path $Path)) {
        Write-Information "Get-CIPPLicenseCatalog: catalog not found at $Path"
        return [pscustomobject]@{ meta = [pscustomobject]@{}; capabilities = @(); families = @(); products = @() }
    }

    $Catalog = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $script:CIPPLicenseCatalog = $Catalog
    return $Catalog
}

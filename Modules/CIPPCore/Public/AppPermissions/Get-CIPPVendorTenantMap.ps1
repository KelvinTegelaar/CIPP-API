function Get-CIPPVendorTenantMap {
    <#
    .SYNOPSIS
        Returns Config/VendorTenantList.json as a tenant ID -> vendor lookup.
    .DESCRIPTION
        The tenants that own the multi-tenant apps of known vendors, with each vendor's name, company,
        category and type (Microsoft, MSP or Business). Parsed once per worker and re-read when the file changes.
        The frontend keeps the same list in src/data/vendorTenantList.json.
    #>
    [CmdletBinding()]
    param()

    $Path = Join-Path $env:CIPPRootPath 'Config/VendorTenantList.json'
    $Stamp = [System.IO.File]::GetLastWriteTimeUtc($Path)
    $Cached = $script:CIPPVendorTenantMap
    if ($Cached -and $Cached.Path -eq $Path -and $Cached.Stamp -eq $Stamp) { return $Cached.Map }

    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Vendor in @([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop)) {
        if (-not $Vendor.vendorTenantId) { continue }
        $Map[[string]$Vendor.vendorTenantId] = [PSCustomObject]@{
            Name       = [string]$Vendor.vendorName
            Company    = [string]$Vendor.companyName
            Category   = [string]$Vendor.category
            VendorType = [string]$Vendor.vendorType
            Website    = [string]$Vendor.website
        }
    }

    $script:CIPPVendorTenantMap = [PSCustomObject]@{ Path = $Path; Stamp = $Stamp; Map = $Map }
    return $Map
}

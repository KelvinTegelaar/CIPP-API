function Resolve-CippBulkSelectedTenant {
    <#
    .SYNOPSIS
        Resolve a bulk request's selectedTenants to tenant records the caller is allowed to write to.

    .DESCRIPTION
        selectedTenants entries carry both a customerId and a defaultDomainName from the request
        body, so neither can be trusted on its own. Each entry is resolved by customerId against
        Get-Tenants and the domain is taken from that record; entries that do not resolve, whose
        body domain disagrees with the record, or that fall outside the caller's scope are dropped.

        An AllTenants entry returns the AllTenants sentinel only for an unrestricted caller, since
        downstream code expands the sentinel to every tenant. A scoped caller gets their allowed
        tenants instead.

    .PARAMETER Request
        The HTTP request, used to resolve the caller's tenant scope.

    .PARAMETER SelectedTenants
        The request body's selectedTenants entries, each carrying a customerId and defaultDomainName.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Request, $SelectedTenants)

    $Allowed = @(Test-CippAccess -Request $Request -TenantList | Where-Object { $_ })
    $Unrestricted = $Allowed -contains 'AllTenants'
    $AllowedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$Allowed, [System.StringComparer]::OrdinalIgnoreCase)

    $All = @(Get-Tenants -IncludeErrors)
    $ById = @{}
    foreach ($Tenant in $All) {
        if ($Tenant.customerId) { $ById[[string]$Tenant.customerId] = $Tenant }
    }

    if ($SelectedTenants | Where-Object { $_.customerId -eq 'AllTenants' -or $_.defaultDomainName -eq 'AllTenants' }) {
        if ($Unrestricted) {
            return [pscustomobject]@{ customerId = 'AllTenants'; defaultDomainName = 'AllTenants' }
        }
        return $All | Where-Object { $_.customerId -and $AllowedSet.Contains([string]$_.customerId) }
    }

    foreach ($Entry in $SelectedTenants) {
        $Record = if ($Entry.customerId) { $ById[[string]$Entry.customerId] }
        if (-not $Record) { continue }
        if ($Entry.defaultDomainName -and $Entry.defaultDomainName -ne $Record.defaultDomainName) { continue }
        if (-not $Unrestricted -and -not $AllowedSet.Contains([string]$Record.customerId)) { continue }
        $Record
    }
}

function Invoke-CIPPBaselineSPOTenant {
    <#
    .SYNOPSIS
        SPOTenant executor: applies tenant-level SharePoint settings through SPO CSOM.
    .DESCRIPTION
        For the SPOTenant properties that have no Graph write path. The spec is
        { properties, methods }: properties is a flat object handed to Set-CIPPSPOTenant
        as SetProperty actions, methods is an ordered array of
        { name, parameters: [{ type, value }] } CSOM method invocations (e.g.
        SetFileVersionPolicy). CSOM enums are NUMERIC on both the read (the SPOTenant
        cache stores Get-CIPPSPOTenant raw output) and the write side, so definitions
        model enum settings as numeric variables (autoComplete options carry the numeric
        CSOM values) - no representation mapping needed. JSON round-trips integers as
        Int64, which Set-CIPPSPOTenant's Int32 whitelist would silently drop, so values
        are coerced before the call. The spec arrives fully rendered.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        # The read result. Unused here; every executor takes the same arguments.
        $Current
    )

    # CSOM property writes accept Boolean/String/Int32 only.
    $Coerce = {
        param($Value)
        if ($Value -is [bool]) { return $Value }
        if ($Value -is [int64] -or $Value -is [int32] -or $Value -is [int16]) { return [int]$Value }
        if ($Value -is [double] -and $Value -eq [math]::Truncate($Value)) { return [int]$Value }
        return [string]$Value
    }

    # Fresh identity every run - the CSOM ObjectIdentity is connection-scoped and must
    # not come from a stale cache row.
    $SPOTenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter
    if (-not $SPOTenant) { throw "Could not resolve the SharePoint tenant object for $TenantFilter." }

    $Properties = @{}
    foreach ($Property in ($Remediate.properties ?? [PSCustomObject]@{}).PSObject.Properties) {
        $Properties[$Property.Name] = & $Coerce $Property.Value
    }
    if ($Properties.Count -gt 0) {
        $null = $SPOTenant | Set-CIPPSPOTenant -Properties $Properties
    }

    foreach ($Method in @($Remediate.methods)) {
        if (-not $Method) { continue }
        $MethodParameters = @(foreach ($Parameter in @($Method.parameters)) {
                @{ Type = $Parameter.type; Value = (& $Coerce $Parameter.value) }
            })
        $null = $SPOTenant | Set-CIPPSPOTenant -MethodName $Method.name -MethodParameters $MethodParameters
    }
}

function Get-CIPPBaselineAddDMARCToMOERAState {
    <#
    .SYNOPSIS
        Prepare hook for AddDMARCToMOERA: MOERA domains whose DMARC record is missing or differs from the configured value.
    .DESCRIPTION
        The MoeraDmarc cache holds one row per domain. A declarative read grades only the first
        row, so every MOERA domain is graded here and the failing ones are named.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Rows = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'MoeraDmarc')
    if ($Rows.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'MoeraDmarc')) {
        return @{ Current = $null }
    }

    $Desired = "$($Item.Variables.RecordValue)"
    $NonCompliant = @(foreach ($Row in $Rows) {
            if (-not $Row.hasDmarc -or "$($Row.record)" -ne $Desired) { "$($Row.domain)" }
        }) | Sort-Object

    @{
        Expected = [PSCustomObject]@{ domainsWithoutDmarc = @() }
        Current  = [PSCustomObject]@{ domainsWithoutDmarc = @($NonCompliant) }
    }
}

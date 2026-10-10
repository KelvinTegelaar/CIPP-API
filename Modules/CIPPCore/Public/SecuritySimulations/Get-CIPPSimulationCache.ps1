function Get-CIPPSimulationCache {
    <#
    .SYNOPSIS
        Reads one CIPPDb cache type for a tenant, collecting it first when it is empty.
    .DESCRIPTION
        The same collect-on-miss rule the Baselines engine applies: a tenant whose cache for a type was
        never collected must not read as "nothing there".
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$Type,
        $Fields
    )

    $Read = {
        if ($Fields) {
            New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type -Fields $Fields | Where-Object { $_ }
        } else {
            New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type | Where-Object { $_ }
        }
    }

    $Rows = @(& $Read)
    if ($Rows.Count -eq 0) {
        $Collector = Get-Command -Name "Set-CIPPDBCache$Type" -ErrorAction SilentlyContinue
        if ($Collector) {
            try {
                $null = & $Collector -TenantFilter $TenantFilter
                $Rows = @(& $Read)
            } catch {
                Write-Information "Get-CIPPSimulationCache: collecting '$Type' for $TenantFilter failed - $($_.Exception.Message)"
            }
        }
    }
    foreach ($Row in $Rows) { $Row }
}

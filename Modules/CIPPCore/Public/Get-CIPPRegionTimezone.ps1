function Get-CIPPRegionTimezone {
    <#
    .SYNOPSIS
    Maps an Azure region to the timezone of the datacentre it runs in.

    .DESCRIPTION
    Looks the region up in Config\RegionTimezoneMap.json and returns its timezone,
    so an instance that has never had a timezone configured can default to something
    local rather than UTC.

    Azure injects the instance's own region as $env:REGION_NAME in the normalised form
    ('eastus', 'northeurope'), which is why that is the default for -Region. ARM's
    'location' property returns the same value for some resources and the display form
    ('East US') for others, so matching is case- and whitespace-insensitive and accepts
    either the Region or the DisplayName column.

    Returns 'UTC' for anything it cannot resolve - an unknown region, an unreadable map,
    or a null/empty input - so callers never have to guard the result.

    The map is duplicated in CIPP-Hosted-Deployments/scripts/region-timezone-map.json,
    which the NG subscription-migration tooling uses for its off-hours window. Keep the
    two copies in sync when Azure adds a region.

    .PARAMETER Region
    Azure region, in either the normalised ('eastus') or display ('East US') form.
    Defaults to $env:REGION_NAME, the region of the instance we are running in.

    .PARAMETER Format
    'IANA' (default) returns e.g. 'America/New_York' - the form CIPP stores and .NET
    resolves natively on Linux. 'Windows' returns e.g. 'Eastern Standard Time'.

    .EXAMPLE
    Get-CIPPRegionTimezone -Region 'eastus'      # America/New_York

    .EXAMPLE
    Get-CIPPRegionTimezone                       # timezone of the region we run in

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Region = $env:REGION_NAME,

        [ValidateSet('IANA', 'Windows')]
        [string]$Format = 'IANA'
    )

    if (-not $script:CIPPRegionTimezoneMap) {
        try {
            $MapPath = Join-Path $env:CIPPRootPath 'Config\RegionTimezoneMap.json'
            $script:CIPPRegionTimezoneMap = [System.IO.File]::ReadAllText($MapPath) | ConvertFrom-Json
        } catch {
            Write-Warning "[RegionTimezone] Could not load RegionTimezoneMap.json: $($_.Exception.Message)"
            return 'UTC'
        }
    }

    if ([string]::IsNullOrWhiteSpace($Region)) {
        return 'UTC'
    }

    # 'East US 2', 'east us 2' and 'eastus2' all normalise to the same key.
    $Key = ($Region -replace '[\s\-_]', '').ToLowerInvariant()
    $Match = $script:CIPPRegionTimezoneMap | Where-Object {
        ([string]$_.Region -replace '[\s\-_]', '').ToLowerInvariant() -eq $Key -or
        ([string]$_.DisplayName -replace '[\s\-_]', '').ToLowerInvariant() -eq $Key
    } | Select-Object -First 1

    if (-not $Match) {
        # Azure adds regions faster than this map is updated. UTC is the safe answer, but
        # log it - this is the only signal that the map needs a new entry.
        Write-Information "[RegionTimezone] Region '$Region' is not in RegionTimezoneMap.json, defaulting to UTC"
        return 'UTC'
    }

    if ($Format -eq 'Windows') {
        return [string]$Match.WindowsTimeZone
    }
    return [string]$Match.TimeZone
}

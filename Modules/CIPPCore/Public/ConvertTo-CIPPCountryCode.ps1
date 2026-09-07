function ConvertTo-CIPPCountryCode {
    <#
    .SYNOPSIS
        Normalises a country value (ISO 3166-1 alpha-2 code or country name) to its code.

    .DESCRIPTION
        Contact templates store the country as a two-letter ISO code - the value field of the
        frontend country picker - but Exchange's Get-Contact returns CountryOrRegion as the full
        country name (e.g. 'United States'). Comparing the two directly always reports a
        difference, so callers normalise both sides through this helper before comparing.

        Resolution is done against Config\CountryList.json - the same list the frontend picker is
        built from (frontend\src\data\countryList.json) - so the code<->name mapping matches what
        produced the stored value. Matching is case-insensitive and accepts either a code or a
        name. Anything that cannot be resolved (unknown value, unreadable list) is returned
        trimmed and upper-cased so a raw comparison still works and no country is silently
        dropped; null/empty input returns $null.

        Keep Config\CountryList.json in sync with frontend\src\data\countryList.json.

    .PARAMETER Country
        A country code ('US') or name ('United States'). Accepts pipeline input.

    .EXAMPLE
        ConvertTo-CIPPCountryCode 'US'                 # US

    .EXAMPLE
        ConvertTo-CIPPCountryCode 'United States'      # US

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Country
    )

    process {
        $Value = "$Country".Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

        if (-not $script:CIPPCountryList) {
            try {
                $ListPath = Join-Path $env:CIPPRootPath 'Config\CountryList.json'
                $script:CIPPCountryList = [System.IO.File]::ReadAllText($ListPath) | ConvertFrom-Json
            } catch {
                Write-Warning "[CountryCode] Could not load CountryList.json: $($_.Exception.Message)"
                return $Value.ToUpperInvariant()
            }
        }

        # -eq on strings is case-insensitive, so 'us'/'US' and 'united states'/'United States' both hit.
        $Match = $script:CIPPCountryList | Where-Object {
            $_.Code -eq $Value -or $_.Name -eq $Value
        } | Select-Object -First 1

        if ($Match) { return [string]$Match.Code }
        return $Value.ToUpperInvariant()
    }
}

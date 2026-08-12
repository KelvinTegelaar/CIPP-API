function Get-CIPPIntuneDefinitionIndex {
    <#
    .SYNOPSIS
        Returns the process-wide index of Intune setting definitions used by Catalog comparisons.
    .DESCRIPTION
        Config/intuneCollection.json is an 18MB single-line array of ~18,000 setting definitions.
        Compare-CIPPIntuneObject used to read and parse the whole file on every call - once per
        Intune template, per tenant - retaining roughly 357MB of managed heap each time. With eight
        background workers comparing concurrently that clears the container's 2,398MB
        DOTNET_GCHeapHardLimit, and the comparison dies with an OutOfMemoryException that the
        standard then reports to the technician as drift.

        A comparison only ever needs two things from a definition: its display name, and the
        id -> display name map of its options. This projects exactly that and nothing else, which
        is about a third of the size of the parsed collection, then hands the same instance to
        every subsequent caller. Callers must treat the result as read-only.

        Lookups are ordinal-case-insensitive to match the -eq comparisons this replaced. Indexing a
        missing key returns $null, the same as the hashtable it replaced; indexing a $null key
        throws, so callers must keep guarding for that.

        The cache is keyed on the file's length and last write time, so a container image that
        ships a new collection is picked up without needing the worker to be recycled.
    .EXAMPLE
        $Index = Get-CIPPIntuneDefinitionIndex
        $Definition = $Index['device_vendor_msft_policy_config_defender_allowrealtimemonitoring']
        $Label = $Definition.displayName
        $Value = $Definition.options['1']
    .NOTES
        Returns $null when the collection is missing, which leaves comparisons falling back to raw
        setting ids rather than failing outright.
    #>
    [CmdletBinding()]
    param()

    # Join-Path, not an interpolated backslash. The two path APIs below disagree about separators
    # on Linux, which is what the container runs: PowerShell's provider normalises '\' to '/', so
    # Get-Item -LiteralPath finds the file, but [System.IO.File] takes the path literally and
    # throws "Could not find file". The index therefore never loaded on any Linux host - the read
    # fell into the catch below and every Catalog comparison silently degraded to raw setting ids,
    # which reads to a technician as drift on every setting of every policy.
    $Path = Join-Path $env:CIPPRootPath 'Config/intuneCollection.json'

    # An index we already hold is always better than none. If the collection cannot be read or
    # parsed right now, keep serving the cached one rather than degrading every comparison to raw
    # setting ids - that reads to a technician as drift on every setting of every policy.
    $File = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $File) {
        if ($script:CIPPIntuneDefinitionIndex) {
            return $script:CIPPIntuneDefinitionIndex
        }
        Write-Information "Intune setting definitions not found at $Path - Catalog comparisons will report raw setting ids."
        return $null
    }

    $Stamp = '{0}|{1}' -f $File.Length, $File.LastWriteTimeUtc.Ticks
    if ($script:CIPPIntuneDefinitionIndex -and $script:CIPPIntuneDefinitionIndexStamp -eq $Stamp) {
        return $script:CIPPIntuneDefinitionIndex
    }

    $Index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    try {
        # ReadAllText over Get-Content: the file is one 18MB line, so Get-Content pays to split it
        # into pipeline objects that ConvertFrom-Json then reassembles. -AsHashtable skips building
        # a PSCustomObject graph that is discarded as soon as the projection below is built.
        $Definitions = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    } catch {
        if ($script:CIPPIntuneDefinitionIndex) {
            Write-Information "Could not parse Intune setting definitions at $Path - keeping the previously loaded definitions. Error: $($_.Exception.Message)"
            return $script:CIPPIntuneDefinitionIndex
        }
        Write-Information "Could not parse Intune setting definitions at $Path - Catalog comparisons will report raw setting ids. Error: $($_.Exception.Message)"
        return $null
    }

    foreach ($Definition in $Definitions) {
        $Id = "$($Definition.id)"
        if (-not $Id) { continue }

        # Definitions without options are the common case; leaving this $null keeps the projection
        # small and lets callers test it before attempting a lookup.
        $Options = $null
        if ($Definition.options) {
            $Options = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Option in $Definition.options) {
                if ($null -eq $Option.id) { continue }
                $Options["$($Option.id)"] = "$($Option.displayName)"
            }
        }

        # A definition with no display name stringifies to '', which is falsy - the call sites
        # already treat that as "no label" and fall back to the setting id.
        $Index[$Id] = @{
            displayName = "$($Definition.displayName)"
            options     = $Options
        }
    }

    # The parsed collection is several times the size of the projection. Drop the reference before
    # returning so it is collectable now rather than whenever this scope happens to unwind.
    $Definitions = $null

    $script:CIPPIntuneDefinitionIndex = $Index
    $script:CIPPIntuneDefinitionIndexStamp = $Stamp

    return $Index
}

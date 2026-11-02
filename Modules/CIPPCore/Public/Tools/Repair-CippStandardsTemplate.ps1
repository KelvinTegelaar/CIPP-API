function Repair-CippStandardsTemplate {
    <#
    .SYNOPSIS
        Recovers a standards template whose JSON failed to parse because of case-insensitive
        duplicate property names, using the standards catalog to decide which key is real, then
        marks the repaired template as safe-by-default. Returns the repaired JSON string, or THROWS
        a descriptive error if it cannot be safely recovered.
    .DESCRIPTION
        PowerShell's ConvertFrom-Json treats property names case-insensitively and throws
        ("...keys with different casing" / "...duplicated keys") when a single object contains two
        names that differ only by case. The known offender is the legacy 'calDefault' standard,
        which was saved with both 'permissionlevel' and 'permissionLevel'.

        This is a targeted recovery routine - call it ONLY from a ConvertFrom-Json catch block. It
        reparses with System.Text.Json (which tolerates duplicate property names) and, for every
        object that has case-colliding keys, consults the standards catalog (Config\standards.json)
        for the owning standard. The colliding key whose exact casing matches a real catalog field
        is kept; the unrecognised duplicate is dropped. So calDefault keeps 'permissionLevel'
        (a real field) and drops the corrupt 'permissionlevel' - rather than blindly guessing.

        Because the repair makes a best-effort choice about corrupt data, the recovered template is
        also neutered so it cannot silently start remediating from an auto-fixed config:
          - templateName is prefixed with "(repaired) ".
          - Drift templates (type -eq 'drift'): autoRemediate is forced to $false on every standard.
          - Regular templates: runManually is forced to $true (the schedule is disabled).

        Non-colliding fields are otherwise untouched, so there is no risk of dropping legitimately
        stored data that the catalog does not enumerate. Arrays, numbers, nulls and nesting are
        preserved exactly (single-element arrays are NOT collapsed).

        If a collision cannot be resolved from the catalog (unknown standard / neither casing is a
        known field), or the JSON is malformed beyond duplicate keys, this function THROWS a
        descriptive terminating error rather than guessing. The caller is expected to log it and
        omit the whole template from the response.
    .PARAMETER Json
        The raw JSON string that failed to parse.
    .PARAMETER Reference
        Optional identifier (e.g. RowKey or template name) included in error/log context.
    .EXAMPLE
        try {
            $Data = $JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        } catch {
            try { $RepairedJson = Repair-CippStandardsTemplate -Json $JSON -Reference $RowKey }
            catch { Write-LogMessage ... -message "Template $RowKey omitted: $($_.Exception.Message)" -Sev Error; return }
            $Data = $RepairedJson | ConvertFrom-Json -Depth 100
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Json,
        [string]$Reference
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw 'Template JSON is empty.'
    }

    # Tolerant reparse. System.Text.Json permits duplicate property names; if even this fails the
    # record is malformed beyond the known duplicate-key issue and is genuinely unrecoverable.
    try {
        $doc = [System.Text.Json.JsonDocument]::Parse($Json)
    } catch {
        throw "Malformed JSON, not recoverable: $($_.Exception.Message)"
    }

    $Schema = Get-CippStandardFieldSchema

    try {
        # Determine drift vs regular (matches CIPP: $Template.type -eq 'drift') to decide how to
        # neuter the repaired template.
        $IsDrift = $false
        if ($doc.RootElement.ValueKind -eq 'Object') {
            foreach ($p in $doc.RootElement.EnumerateObject()) {
                if ($p.Name -eq 'type' -and $p.Value.ValueKind -eq 'String' -and $p.Value.GetString() -eq 'drift') {
                    $IsDrift = $true; break
                }
            }
        }

        $stream = [System.IO.MemoryStream]::new()
        $writer = [System.Text.Json.Utf8JsonWriter]::new($stream)
        try {
            # Write-CippCleanJsonElement throws if it finds a collision it cannot resolve.
            Write-CippCleanJsonElement -Element $doc.RootElement -Writer $writer -Schema $Schema -IsDrift $IsDrift -Context 'root'
            $writer.Flush()
            $clean = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
        } finally { $writer.Dispose() }
    } finally { $doc.Dispose() }

    # Validate the repaired JSON parses cleanly before handing it back; if not, it's unrecoverable.
    try {
        $null = $clean | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    } catch {
        throw "Still unreadable after de-duplicating keys: $($_.Exception.Message)"
    }
    return $clean
}

function Get-CippStandardFieldSchema {
    # Builds (and caches) a map of standard name -> set of valid field names (canonical casing),
    # derived from the addedComponent definitions in Config\standards.json. Used only to decide
    # which member of a case-colliding key pair is the legitimate one.
    if ($script:CippStandardFieldSchema) { return $script:CippStandardFieldSchema }

    $map = @{}
    try {
        $Path = Join-Path $env:CIPPRootPath 'Config\standards.json'
        if (Test-Path $Path) {
            $Catalog = Get-Content $Path -Raw | ConvertFrom-Json -Depth 20
            foreach ($Std in $Catalog) {
                if (-not $Std.name -or $Std.name -notlike 'standards.*') { continue }
                $StandardKey = $Std.name.Substring('standards.'.Length).ToLowerInvariant()
                $Fields = [System.Collections.Generic.HashSet[string]]::new()
                $Prefix = "$($Std.name)."
                foreach ($Component in @($Std.addedComponent)) {
                    if (-not $Component.name) { continue }
                    if ($Component.name -like "$Prefix*") {
                        foreach ($Segment in ($Component.name.Substring($Prefix.Length) -split '\.')) {
                            if ($Segment) { [void]$Fields.Add($Segment) }
                        }
                    }
                }
                $map[$StandardKey] = $Fields
            }
        } else {
            Write-Host "Get-CippStandardFieldSchema: standards catalog not found at $Path"
        }
    } catch {
        Write-Host "Get-CippStandardFieldSchema: failed to build schema: $($_.Exception.Message)"
    }

    $script:CippStandardFieldSchema = $map
    return $map
}

function Write-CippCleanJsonElement {
    # Internal helper for Repair-CippStandardsTemplate. Recursively rewrites a JsonElement,
    # resolving case-insensitive duplicate property names by keeping the catalog-valid casing
    # (throws if it can't), and neutering the repaired template so it won't auto-remediate:
    # renames templateName, forces runManually (regular) or autoRemediate=false (drift).
    param(
        [System.Text.Json.JsonElement]$Element,
        [System.Text.Json.Utf8JsonWriter]$Writer,
        [hashtable]$Schema,
        [bool]$IsDrift = $false,
        [System.Collections.Generic.HashSet[string]]$ValidFields = $null,
        [string]$StandardName = $null,
        [string]$Context = 'root'
    )
    switch ($Element.ValueKind) {
        'Object' {
            $Writer.WriteStartObject()
            $props = @($Element.EnumerateObject())

            # Group property indices by case-insensitive name to detect collisions.
            $byCi = @{}
            for ($i = 0; $i -lt $props.Count; $i++) {
                $ci = $props[$i].Name.ToLowerInvariant()
                if (-not $byCi.ContainsKey($ci)) { $byCi[$ci] = [System.Collections.Generic.List[int]]::new() }
                [void]$byCi[$ci].Add($i)
            }

            # For each collision keep the catalog-valid casing; throw if it can't be resolved.
            $keep = @{}
            foreach ($ci in $byCi.Keys) {
                $indices = $byCi[$ci]
                if ($indices.Count -eq 1) { $keep[$ci] = $indices[0]; continue }
                $chosen = $null
                if ($ValidFields) {
                    foreach ($idx in $indices) {
                        if ($ValidFields.Contains($props[$idx].Name)) { $chosen = $idx; break }
                    }
                }
                if ($null -eq $chosen) {
                    $where = if ($StandardName) { "standard '$StandardName'" } else { 'the template root' }
                    $variants = ($indices | ForEach-Object { "'$($props[$_].Name)'" }) -join ', '
                    throw "Unresolvable duplicate property '$ci' ($variants) in $where - no matching field in the standards catalog to determine the correct value."
                }
                $keep[$ci] = $chosen
            }

            # Safety-neutering overrides to apply to THIS object.
            $forceBool = @{}            # canonical name -> bool value to force
            if ($Context -eq 'root' -and -not $IsDrift) { $forceBool['runManually'] = $true }
            elseif ($Context -eq 'standardEntry' -and $IsDrift) { $forceBool['autoRemediate'] = $false }
            $forceLower = @{}
            foreach ($k in $forceBool.Keys) { $forceLower[$k.ToLowerInvariant()] = $k }
            $pending = [System.Collections.Generic.List[string]]@($forceBool.Keys)

            for ($i = 0; $i -lt $props.Count; $i++) {
                $ci = $props[$i].Name.ToLowerInvariant()
                if ($keep[$ci] -ne $i) { continue }

                $name = $props[$i].Name

                # Force a boolean value (e.g. runManually / autoRemediate) over the stored one.
                if ($forceLower.ContainsKey($ci)) {
                    $Writer.WriteBoolean($name, [bool]$forceBool[$forceLower[$ci]])
                    [void]$pending.Remove($forceLower[$ci])
                    continue
                }

                # Prefix the template name so it's obvious it was auto-repaired.
                if ($Context -eq 'root' -and $ci -eq 'templatename' -and $props[$i].Value.ValueKind -eq 'String') {
                    $orig = $props[$i].Value.GetString()
                    $newName = if ($orig.StartsWith('(repaired) ')) { $orig } else { "(repaired) $orig" }
                    $Writer.WriteString($name, $newName)
                    continue
                }

                $Writer.WritePropertyName($name)

                # Track which standard we are inside so deeper collisions can be resolved/reported
                # and so per-standard neutering can be applied at the standard entry object.
                $childValid = $ValidFields
                $childStandard = $StandardName
                $childContext = 'inside'
                if ($Context -eq 'root' -and $name -eq 'standards') {
                    $childContext = 'container'
                    $childValid = $null
                } elseif ($Context -eq 'container') {
                    $childValid = $Schema[$ci]
                    $childStandard = $name
                    $childContext = 'standardEntry'
                }
                Write-CippCleanJsonElement -Element $props[$i].Value -Writer $Writer -Schema $Schema -IsDrift $IsDrift -ValidFields $childValid -StandardName $childStandard -Context $childContext
            }

            # Inject any forced property that wasn't present in the stored object.
            foreach ($missing in $pending) {
                $Writer.WriteBoolean($missing, [bool]$forceBool[$missing])
            }

            $Writer.WriteEndObject()
        }
        'Array' {
            $Writer.WriteStartArray()
            foreach ($item in $Element.EnumerateArray()) {
                Write-CippCleanJsonElement -Element $item -Writer $Writer -Schema $Schema -IsDrift $IsDrift -ValidFields $ValidFields -StandardName $StandardName -Context 'inside'
            }
            $Writer.WriteEndArray()
        }
        default { $Element.WriteTo($Writer) }
    }
}

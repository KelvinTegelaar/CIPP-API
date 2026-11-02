function ConvertTo-CIPPSensitiveInformationType {
    <#
    .SYNOPSIS
        Normalize a DLP rule's ContentContainsSensitiveInformation value into clean input objects.
    .DESCRIPTION
        Get-DlpComplianceRule returns ContentContainsSensitiveInformation (and the ExceptIf variant)
        in an output-only @odata serialization that New-/Set-DlpComplianceRule will not accept as input.
        Two shapes occur:

          - Flat list: an array of SITs, each SIT being an array of '{ _key, _value }' GenericHashTable
            pairs - e.g. { _key = 'name'; _value = 'Credit Card Number' }.

          - Grouped: an array containing a single wrapper '{ groups = (...); operator = 'And' }', where
            each group is an array of pairs carrying 'name', 'operator', and a nested 'sensitivetypes'
            value (itself a flat list of SITs). Used by templates that AND/OR several named groups
            together (e.g. HIPAA Enhanced). NOTE the wrapper is delivered inside an array, so the
            top-level value is an array in BOTH shapes.

        This collapses every '{ _key, _value }' pair group into a single flat object and recurses through
        the grouped / groups / sensitivetypes nesting, producing a structure the New-/Set-* cmdlets accept.

        The function is idempotent: a value already in the clean shape (no '_key' pairs) is returned
        unchanged, so it is safe to call at both template-build time and deploy time.
    .PARAMETER SensitiveInformation
        The ContentContainsSensitiveInformation value to normalize.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($SensitiveInformation)

    if ($null -eq $SensitiveInformation) { return $null }

    # Output-only SIT properties that Get-DlpComplianceRule emits but New-/Set-DlpComplianceRule reject
    # as input (matched case-insensitively against the lower-cased key).
    $script:InvalidSitProperties = @('rulepackid')

    # Recursively normalize a single entry. An entry is one of:
    #   - a raw array of { _key, _value } pairs (a SIT, or a group)  -> collapse to a flat object
    #   - a grouped wrapper object { groups, operator }              -> recurse each group
    #   - an already-clean object with a nested sensitivetypes list  -> recurse that list
    #   - anything else                                              -> pass through unchanged
    # 'groups' and 'sensitivetypes' are recursed on BOTH the raw and the already-clean paths so the
    # conversion is correct whether the wrapper arrives bare or (as the cmdlets deliver it) array-wrapped,
    # and so re-running on an already-converted value is a no-op.
    function Convert-Entry {
        param($Entry)

        if ($null -eq $Entry) { return $null }

        $first = @($Entry) | Where-Object { $null -ne $_ } | Select-Object -First 1
        $isRawPairs = ($Entry -isnot [string]) -and $null -ne $first -and ($first.PSObject.Properties.Name -contains '_key')

        if ($isRawPairs) {
            $ht = [ordered]@{}
            foreach ($pair in @($Entry)) {
                if ($null -eq $pair -or ($pair.PSObject.Properties.Name -notcontains '_key')) { continue }
                $key = [string]$pair._key
                # Skip output-only properties the New-/Set-* cmdlets reject as input (e.g. rulePackId,
                # which Get-DlpComplianceRule emits on every SIT).
                if ($key -in $script:InvalidSitProperties) { continue }
                if ($key -in @('sensitivetypes', 'groups')) {
                    $ht[$key] = @(foreach ($child in @($pair._value)) { Convert-Entry -Entry $child })
                } else {
                    $ht[$key] = $pair._value
                }
            }
            return [pscustomobject]$ht
        }

        # Already clean (or partially clean) object - recurse the nested collections, strip invalid
        # properties, pass the rest through. Rebuild when there is anything to recurse or strip.
        $propNames = @($Entry.PSObject.Properties.Name)
        $needsRebuild = ($propNames | Where-Object { $_ -in @('groups', 'sensitivetypes') -or $_ -in $script:InvalidSitProperties }).Count -gt 0
        if ($needsRebuild) {
            $clone = [ordered]@{}
            foreach ($prop in $Entry.PSObject.Properties) {
                if ($prop.Name -in $script:InvalidSitProperties) { continue }
                if ($prop.Name -in @('groups', 'sensitivetypes')) {
                    $clone[$prop.Name] = @(foreach ($child in @($prop.Value)) { Convert-Entry -Entry $child })
                } else {
                    $clone[$prop.Name] = $prop.Value
                }
            }
            return [pscustomobject]$clone
        }

        return $Entry
    }

    # Grouped form: a bare wrapper object exposing a 'groups' collection. (When array-wrapped, the
    # branch below handles it via Convert-Entry on each element.)
    if ($SensitiveInformation -isnot [System.Collections.IEnumerable] -and
        ($SensitiveInformation.PSObject.Properties.Name -contains 'groups')) {
        # Callers MUST wrap the result in @(...) so this lands as a PswsHashtable[] array on the wire -
        # PowerShell unwraps a single-element return to a bare object, which is rejected server-side.
        return @(Convert-Entry -Entry $SensitiveInformation)
    }

    # Array form (the normal case): flat list of SITs, OR an array carrying the grouped wrapper.
    # Callers must wrap in @(...) - see the note above.
    return @(foreach ($entry in @($SensitiveInformation)) { Convert-Entry -Entry $entry })
}

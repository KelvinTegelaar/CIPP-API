function Remove-CIPPStandardSettingsRawData {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Strips the UI-only rawData snapshot out of a standard's settings.
    .DESCRIPTION
        CippAutocomplete attaches the entire API row an option was built from to the selected value,
        as .rawData. For a template picker that row is the whole template, so an Intune template
        standard carries a second copy of the policy payload - for a large baseline, hundreds of KB
        of JSON nested inside the settings as an escaped string.

        Nothing reads it once the standard runs. The standards resolve their template from the
        templates table by GUID, and Get-CIPPStandards already builds tag-expanded items carrying
        nothing but label and value - which is why deploying a package of templates worked while
        deploying the same template on its own did not.

        Dropping it before the settings are round-tripped through JSON for variable replacement
        keeps the payload small and keeps a nested JSON document, which needs a different amount of
        escaping than the document it sits in, out of the replacement path entirely.
    .PARAMETER Settings
        The settings object for a single standard. Hashtables and PSCustomObjects are both accepted,
        since the queue item is deserialized JSON.
    .EXAMPLE
        $Clean = Remove-CIPPStandardSettingsRawData -Settings $Item.Settings
    #>
    [CmdletBinding()]
    param($Settings)

    # Returns a value with its rawData snapshot removed. Anything that is not an autocomplete
    # selection is handed straight back, so this is safe to run over every setting a standard has.
    function Remove-CIPPRawDataMember {
        param($Value)

        if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $Value }

        if ($Value -is [System.Collections.IDictionary]) {
            if (-not $Value.Contains('rawData')) { return $Value }
            $Copy = @{}
            foreach ($Key in $Value.Keys) {
                if ($Key -ne 'rawData') { $Copy[$Key] = $Value[$Key] }
            }
            return $Copy
        }

        # A multi-select autocomplete stores an array of selections.
        if ($Value -is [System.Collections.IEnumerable]) {
            return @(foreach ($Entry in $Value) { Remove-CIPPRawDataMember -Value $Entry })
        }

        if ($Value.PSObject.Properties['rawData']) {
            $Copy = $Value.PSObject.Copy()
            $Copy.PSObject.Properties.Remove('rawData')
            return $Copy
        }

        return $Value
    }

    if ($null -eq $Settings) { return $Settings }

    if ($Settings -is [System.Collections.IDictionary]) {
        $Result = @{}
        foreach ($Key in $Settings.Keys) {
            $Result[$Key] = Remove-CIPPRawDataMember -Value $Settings[$Key]
        }
        return $Result
    }

    # Rebuilt rather than copied so the caller's object is never mutated - Push-CIPPStandard still
    # reads the original for its telemetry after this runs.
    if ($Settings -is [System.Management.Automation.PSObject] -or $Settings -is [psobject]) {
        $Result = [pscustomobject]@{}
        foreach ($Property in $Settings.PSObject.Properties) {
            $Result | Add-Member -NotePropertyName $Property.Name -NotePropertyValue (Remove-CIPPRawDataMember -Value $Property.Value) -Force
        }
        return $Result
    }

    return $Settings
}

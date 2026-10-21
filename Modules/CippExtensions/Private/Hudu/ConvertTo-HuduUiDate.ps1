function ConvertTo-HuduUiDate {
    <#
        .SYNOPSIS
        Parses a Graph date value to UTC, or returns $null when it is empty or unparseable.
    #>
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc) }
        return $Value.ToUniversalTime()
    }
    $Parsed = [datetime]::MinValue
    $Styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetime]::TryParse([string]$Value, [cultureinfo]::InvariantCulture, $Styles, [ref]$Parsed)) { return $Parsed }
    return $null
}

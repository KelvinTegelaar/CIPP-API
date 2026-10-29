function ConvertTo-CippExtensionUiText {
    <#
        .SYNOPSIS
        HTML-encodes a value for use in element text or a quoted attribute.

        .DESCRIPTION
        Characters above U+007F are written as numeric entities so the output is ASCII only.
    #>
    param([Parameter(ValueFromPipeline)][AllowNull()][object]$Value)
    process {
        $Encoded = [System.Net.WebUtility]::HtmlEncode([string]$Value)
        if ($Encoded -notmatch '[^\x00-\x7F]') { return $Encoded }
        $Sb = [System.Text.StringBuilder]::new()
        for ($i = 0; $i -lt $Encoded.Length; $i++) {
            $c = $Encoded[$i]
            if ([int]$c -lt 128) { [void]$Sb.Append($c) }
            elseif ([char]::IsHighSurrogate($c) -and ($i + 1) -lt $Encoded.Length) {
                [void]$Sb.Append('&#').Append([char]::ConvertToUtf32($c, $Encoded[$i + 1])).Append(';'); $i++
            } else { [void]$Sb.Append('&#').Append([int]$c).Append(';') }
        }
        $Sb.ToString()
    }
}

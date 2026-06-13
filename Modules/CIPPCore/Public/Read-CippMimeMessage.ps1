function Read-CippMimeMessage {
    <#
    .SYNOPSIS
        Extract URLs and attachments from a raw MIME message.
    .DESCRIPTION
        Pure PowerShell MIME parser for common quarantine EML structures. Handles nested
        multipart messages, base64 and quoted-printable bodies, and common filename
        parameters. RFC 2231 split filenames, exotic charset conversions, and TNEF
        winmail.dat payloads are not fully handled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    $Urls = [System.Collections.Generic.List[object]]::new()
    $Attachments = [System.Collections.Generic.List[object]]::new()
    $UrlKeys = @{}

    function Split-CippMimeEntity {
        param([AllowEmptyString()][string]$EntityText)

        $Match = [regex]::Match($EntityText, "\r?\n\r?\n")
        if ($Match.Success) {
            $HeaderText = $EntityText.Substring(0, $Match.Index)
            $BodyText = $EntityText.Substring($Match.Index + $Match.Length)
        } else {
            $HeaderText = $EntityText
            $BodyText = ''
        }

        $Headers = @{}
        $UnfoldedHeaders = $HeaderText -replace "(?m)\r?\n[ \t]+", ' '
        foreach ($Line in ($UnfoldedHeaders -split "\r?\n")) {
            if ($Line -match '^\s*([^:]+):\s*(.*)$') {
                $Name = $Matches[1].Trim()
                $Value = $Matches[2].Trim()
                if ($Headers.ContainsKey($Name)) {
                    $Headers[$Name] = @($Headers[$Name], $Value) -join ', '
                } else {
                    $Headers[$Name] = $Value
                }
            }
        }

        [PSCustomObject]@{
            Headers = $Headers
            Body    = $BodyText
        }
    }

    function ConvertFrom-CippMimeQuotedString {
        param([AllowEmptyString()][string]$Value)

        $Trimmed = $Value.Trim()
        if ($Trimmed.Length -ge 2 -and $Trimmed.StartsWith('"') -and $Trimmed.EndsWith('"')) {
            $Trimmed = $Trimmed.Substring(1, $Trimmed.Length - 2)
            $Trimmed = $Trimmed -replace '\\(.)', '$1'
        }

        $Trimmed
    }

    function ConvertFrom-CippMimeExtendedParameter {
        param([AllowEmptyString()][string]$Value)

        $Decoded = ConvertFrom-CippMimeQuotedString -Value $Value
        if ($Decoded -match "^([^']*)'[^']*'(.*)$") {
            $Charset = $Matches[1]
            $EncodedValue = $Matches[2]
            try {
                $Unescaped = [System.Uri]::UnescapeDataString($EncodedValue)
                if (![string]::IsNullOrWhiteSpace($Charset)) {
                    try {
                        $Encoding = [System.Text.Encoding]::GetEncoding($Charset)
                        $Bytes = [System.Text.Encoding]::Latin1.GetBytes($Unescaped)
                        return $Encoding.GetString($Bytes)
                    } catch {
                        return $Unescaped
                    }
                }
                return $Unescaped
            } catch {
                return $Decoded
            }
        }

        $Decoded
    }

    function Split-CippMimeHeaderParameters {
        param([AllowEmptyString()][string]$HeaderValue)

        $Segments = [System.Collections.Generic.List[string]]::new()
        $Current = [System.Text.StringBuilder]::new()
        $InQuotes = $false
        $Escaped = $false

        foreach ($Char in $HeaderValue.ToCharArray()) {
            if ($Escaped) {
                [void]$Current.Append($Char)
                $Escaped = $false
                continue
            }

            if ($Char -eq '\' -and $InQuotes) {
                [void]$Current.Append($Char)
                $Escaped = $true
                continue
            }

            if ($Char -eq '"') {
                [void]$Current.Append($Char)
                $InQuotes = !$InQuotes
                continue
            }

            if ($Char -eq ';' -and !$InQuotes) {
                $Segments.Add($Current.ToString().Trim())
                [void]$Current.Clear()
                continue
            }

            [void]$Current.Append($Char)
        }
        $Segments.Add($Current.ToString().Trim())

        $Parameters = @{}
        for ($Index = 1; $Index -lt $Segments.Count; $Index++) {
            $Key, $Value = $Segments[$Index] -split '=', 2
            if ([string]::IsNullOrWhiteSpace($Key) -or $null -eq $Value) { continue }

            $ParameterName = $Key.Trim().ToLowerInvariant()
            if ($ParameterName.EndsWith('*')) {
                $Parameters[$ParameterName] = ConvertFrom-CippMimeExtendedParameter -Value $Value
            } else {
                $Parameters[$ParameterName] = ConvertFrom-CippMimeQuotedString -Value $Value
            }
        }

        [PSCustomObject]@{
            Value      = ($Segments[0] ?? '').Trim().ToLowerInvariant()
            Parameters = $Parameters
        }
    }

    function Split-CippMimeMultipartBody {
        param(
            [AllowEmptyString()][string]$Body,
            [Parameter(Mandatory = $true)][string]$Boundary
        )

        $Parts = [System.Collections.Generic.List[string]]::new()
        $BoundaryPattern = '^--' + [regex]::Escape($Boundary) + '(?<Closing>--)?[ \t]*$'
        $CurrentLines = [System.Collections.Generic.List[string]]::new()
        $InPart = $false

        foreach ($Line in ($Body -split "\r?\n")) {
            $BoundaryMatch = [regex]::Match($Line, $BoundaryPattern)
            if ($BoundaryMatch.Success) {
                if ($InPart) {
                    $Parts.Add(($CurrentLines -join "`r`n"))
                    $CurrentLines.Clear()
                }
                if ($BoundaryMatch.Groups['Closing'].Success) {
                    break
                }
                $InPart = $true
                continue
            }

            if ($InPart) {
                $CurrentLines.Add($Line)
            }
        }

        @($Parts)
    }

    function ConvertFrom-CippMimeQuotedPrintable {
        param([AllowEmptyString()][string]$Body)

        $Stream = [System.IO.MemoryStream]::new()
        try {
            for ($Index = 0; $Index -lt $Body.Length; $Index++) {
                $Char = $Body[$Index]
                if ($Char -eq '=' -and ($Index + 1) -lt $Body.Length) {
                    if ($Body[$Index + 1] -eq "`r" -and ($Index + 2) -lt $Body.Length -and $Body[$Index + 2] -eq "`n") {
                        $Index += 2
                        continue
                    }
                    if ($Body[$Index + 1] -eq "`n") {
                        $Index += 1
                        continue
                    }
                    if (($Index + 2) -lt $Body.Length) {
                        $Hex = $Body.Substring($Index + 1, 2)
                        if ($Hex -match '^[0-9A-Fa-f]{2}$') {
                            $Stream.WriteByte([Convert]::ToByte($Hex, 16))
                            $Index += 2
                            continue
                        }
                    }
                }

                $Bytes = [System.Text.Encoding]::Latin1.GetBytes([string]$Char)
                $Stream.Write($Bytes, 0, $Bytes.Length)
            }

            $Stream.ToArray()
        } finally {
            $Stream.Dispose()
        }
    }

    function ConvertTo-CippMimeBodyBytes {
        param(
            [AllowEmptyString()][string]$Body,
            [AllowEmptyString()][string]$TransferEncoding
        )

        switch -Regex (($TransferEncoding ?? '').Trim().ToLowerInvariant()) {
            '^base64$' {
                return [Convert]::FromBase64String(($Body -replace '\s+', ''))
            }
            '^quoted-printable$' {
                return ConvertFrom-CippMimeQuotedPrintable -Body $Body
            }
            default {
                return [System.Text.Encoding]::Latin1.GetBytes($Body)
            }
        }
    }

    function ConvertTo-CippMimeText {
        param(
            [byte[]]$Bytes,
            [AllowEmptyString()][string]$Charset
        )

        if ($null -eq $Bytes) { return '' }
        if (![string]::IsNullOrWhiteSpace($Charset)) {
            try {
                return [System.Text.Encoding]::GetEncoding($Charset).GetString($Bytes)
            } catch {
                return [System.Text.Encoding]::UTF8.GetString($Bytes)
            }
        }

        [System.Text.Encoding]::UTF8.GetString($Bytes)
    }

    function Add-CippMimeUrl {
        param([AllowEmptyString()][string]$Url)

        if ([string]::IsNullOrWhiteSpace($Url)) { return }
        $CleanUrl = [System.Net.WebUtility]::HtmlDecode($Url).Trim()
        $CleanUrl = $CleanUrl.TrimEnd('.', ',', ';', ':', '!', '?', ')', ']', '}')
        if ($CleanUrl -notmatch '^https?://') { return }
        if ($UrlKeys.ContainsKey($CleanUrl)) { return }

        $UrlKeys[$CleanUrl] = $true
        $Urls.Add([PSCustomObject]@{
                url             = $CleanUrl
                threatType      = $null
                detectionMethod = $null
            })
    }

    function Add-CippMimeUrlsFromText {
        param([AllowEmptyString()][string]$Text)

        $HrefPattern = "(?i)\bhref\s*=\s*(?:""(?<url>https?://[^""]+)""|'(?<url>https?://[^']+)'|(?<url>https?://[^\s>]+))"
        foreach ($Match in [regex]::Matches($Text, $HrefPattern)) {
            Add-CippMimeUrl -Url $Match.Groups['url'].Value
        }

        $BarePattern = '(?i)\bhttps?://[^\s<>"'']+'
        foreach ($Match in [regex]::Matches($Text, $BarePattern)) {
            Add-CippMimeUrl -Url $Match.Value
        }
    }

    function Get-CippMimeSha256 {
        param([byte[]]$Bytes)

        $Sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            ([BitConverter]::ToString($Sha256.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
        } finally {
            $Sha256.Dispose()
        }
    }

    function Read-CippMimePart {
        param([AllowEmptyString()][string]$EntityText)

        $Entity = Split-CippMimeEntity -EntityText $EntityText
        $ContentType = Split-CippMimeHeaderParameters -HeaderValue ($Entity.Headers['Content-Type'] ?? 'text/plain')
        $ContentDisposition = Split-CippMimeHeaderParameters -HeaderValue ($Entity.Headers['Content-Disposition'] ?? '')
        $Boundary = $ContentType.Parameters['boundary']

        if ($ContentType.Value -like 'multipart/*' -and ![string]::IsNullOrWhiteSpace($Boundary)) {
            foreach ($Part in (Split-CippMimeMultipartBody -Body $Entity.Body -Boundary $Boundary)) {
                Read-CippMimePart -EntityText $Part
            }
            return
        }

        if ($ContentType.Value -eq 'message/rfc822') {
            Read-CippMimePart -EntityText $Entity.Body
            return
        }

        $FileName = $ContentDisposition.Parameters['filename*'] ??
            $ContentDisposition.Parameters['filename'] ??
            $ContentType.Parameters['name*'] ??
            $ContentType.Parameters['name']
        $IsAttachment = ![string]::IsNullOrWhiteSpace($FileName) -or $ContentDisposition.Value -eq 'attachment'
        $Bytes = ConvertTo-CippMimeBodyBytes -Body $Entity.Body -TransferEncoding $Entity.Headers['Content-Transfer-Encoding']

        if ($IsAttachment) {
            $Attachments.Add([PSCustomObject]@{
                    fileName    = $FileName
                    contentType = $ContentType.Value
                    fileSize    = $Bytes.Length
                    sha256      = Get-CippMimeSha256 -Bytes $Bytes
                    threatType  = $null
                })
            return
        }

        if ($ContentType.Value -in @('text/plain', 'text/html')) {
            $Text = ConvertTo-CippMimeText -Bytes $Bytes -Charset $ContentType.Parameters['charset']
            Add-CippMimeUrlsFromText -Text $Text
        }
    }

    Read-CippMimePart -EntityText $Message

    [PSCustomObject]@{
        urls        = @($Urls)
        attachments = @($Attachments)
    }
}

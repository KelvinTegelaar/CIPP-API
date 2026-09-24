function Test-CIPPGraphEndpointBlocked {
    <#
    .SYNOPSIS
        Returns true when a Graph path is on the customer-content blocklist.
    .DESCRIPTION
        Used wherever an arbitrary Graph path is accepted (Get-GraphRequestList, which backs
        ListGraphRequest and scheduled tasks, and ListGraphBulkRequest) so operators and MCP cannot
        pull mailbox, chat, drive, or other customer content through Graph Explorer-style proxies.

        The path and any $expand/expand values (from the query string or -Expand) are
        percent-decoded before matching, because Graph decodes them server-side.
    .PARAMETER Uri
        Full Graph URI or relative endpoint (host/version stripped before match).
    .PARAMETER Expand
        $expand / expand values passed separately from the Uri.
    .PARAMETER Throw
        If set, throw when blocked. Message includes the matched entry id and reason.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Uri,

        [string[]]$Expand,

        [switch]$Throw
    )

    function ConvertFrom-CippEncodedGraphText([string]$Text) {
        for ($i = 0; $i -lt 5; $i++) {
            $Decoded = [System.Uri]::UnescapeDataString($Text)
            if ($Decoded -eq $Text) { break }
            $Text = $Decoded
        }
        return $Text
    }

    # An $expand expression like "fields,driveItem($select=id)" is matched as path segments under the
    # resource it expands, so patterns that need a parent (planner/.../tasks, lists/.../items) still apply.
    function ConvertTo-CippExpandPath([string]$Text) {
        return $ExpandPrefix + ((ConvertFrom-CippEncodedGraphText $Text) -replace '[,();=]', '/')
    }

    $Candidates = [System.Collections.Generic.List[string]]::new()
    $ExpandPrefix = '$expand/'

    if (-not [string]::IsNullOrWhiteSpace($Uri)) {
        # Parse the way the HTTP client will send it: fragment dropped, \ becomes /, dot segments resolved.
        $Text = $Uri.Trim()
        if ($Text -notmatch '^https?://') {
            $Text = 'https://graph.microsoft.com/v1.0/' + ($Text -replace '^[/\\]+', '')
        }
        $Parsed = $null
        if ([System.Uri]::TryCreate($Text, [System.UriKind]::Absolute, [ref]$Parsed)) {
            $Raw = $Parsed.AbsolutePath -replace '^/(v1\.0|beta)(?=/|$)', ''
            $Query = $Parsed.Query -replace '^\?', ''
        } else {
            $Raw, $Query = ($Text -replace '^https?://[^/]+/(v1\.0|beta)/?', '' -replace '#.*$', '') -split '\?', 2
        }
        # Trailing dots/whitespace on a segment are dropped by some front ends, so ignore them when matching.
        $Path = (ConvertFrom-CippEncodedGraphText $Raw) -replace '\\', '/' -replace '[.\s]+(?=/|$)', '' -replace '^/+', ''
        if ($Path) {
            $Candidates.Add($Path)
            $ExpandPrefix = '{0}/$expand/' -f $Path.TrimEnd('/')
        }

        foreach ($Pair in ($Query -split '&')) {
            $Key, $Value = $Pair -split '=', 2
            if ((ConvertFrom-CippEncodedGraphText $Key) -in @('$expand', 'expand') -and $Value) {
                $Candidates.Add((ConvertTo-CippExpandPath $Value))
            }
        }
    }

    foreach ($Value in @($Expand)) {
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            $Candidates.Add((ConvertTo-CippExpandPath $Value))
        }
    }

    if ($Candidates.Count -eq 0) {
        return $false
    }

    if ($null -eq $script:CippGraphEndpointBlocklist) {
        $BlocklistPath = Join-Path -Path $env:CIPPRootPath -ChildPath 'Config\GraphEndpointBlocklist.json'
        $Blocklist = [System.IO.File]::ReadAllText($BlocklistPath) | ConvertFrom-Json
        $RegexOptions = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
        $script:CippGraphEndpointBlocklist = @(
            foreach ($Entry in @($Blocklist.blockedEndpoints)) {
                if (-not $Entry.pattern) { continue }
                [pscustomobject]@{
                    id     = $Entry.id
                    reason = $Entry.reason
                    Regex  = [regex]::new($Entry.pattern, $RegexOptions)
                }
            }
        )
    }

    foreach ($Candidate in $Candidates) {
        foreach ($Entry in $script:CippGraphEndpointBlocklist) {
            if ($Entry.Regex.IsMatch($Candidate)) {
                $Message = 'Graph endpoint blocked ({0}): {1}' -f $Entry.id, $Entry.reason
                Write-Information $Message
                if ($Throw) {
                    throw $Message
                }
                return $true
            }
        }
    }

    return $false
}

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

    # Decode until stable (every pass shortens the string, so it terminates), including IIS-style %uXXXX.
    # Whitespace, control and format characters (NUL, zero-width space) are then dropped: Graph either
    # ignores them or 404s, so removing them before matching can only fail closed.
    function ConvertFrom-CippEncodedGraphText([string]$Text) {
        do {
            $Previous = $Text
            $Text = [regex]::Replace([System.Uri]::UnescapeDataString($Text), '%u([0-9a-f]{4})', {
                    [string][char][Convert]::ToInt32($args[0].Groups[1].Value, 16)
                }, 'IgnoreCase')
        } while ($Text -ne $Previous)
        return $Text -replace '[\s\p{C}]+', ''
    }

    # \ ? and # become separators (a front end or a second decode may honour them), and trailing dots on
    # a segment are dropped, since some front ends strip them.
    function ConvertTo-CippGraphMatchPath([string]$Text) {
        return $Text -replace '[\\?#]', '/' -replace '\.+(?=[/(;]|$)', '' -replace '^/+', ''
    }

    # An $expand expression like "fields,driveItem($select=id)" is matched as path segments under the
    # resource it expands, so patterns that need a parent (planner/.../tasks, lists/.../items) still apply.
    # Anything that is not part of a property name is a separator, so "fields, driveItem" and
    # "fields,+driveItem" (+ is a space in a query string) cannot hide the segment boundary.
    function ConvertTo-CippExpandPath([string]$Text) {
        return ConvertTo-CippGraphMatchPath ($ExpandPrefix + ((ConvertFrom-CippEncodedGraphText $Text) -replace '[^\w.$@-]', '/'))
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
        $Path = ConvertTo-CippGraphMatchPath (ConvertFrom-CippEncodedGraphText $Raw)
        if ($Path) {
            $Candidates.Add($Path)
            $ExpandPrefix = '{0}/$expand/' -f $Path.TrimEnd('/')
        }

        foreach ($Pair in ($Query -split '&')) {
            $Key, $Value = $Pair -split '=', 2
            # Loose on purpose (catches "?$expand", "$Expand ", "%2524expand"): a false hit only means the
            # value is checked too.
            if ((ConvertFrom-CippEncodedGraphText $Key) -match 'expand' -and $Value) {
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
        # Patterns like lists(?=[/(]).*/items backtrack quadratically on crafted input; cap each match.
        $MatchTimeout = [timespan]::FromMilliseconds(250)
        $Entries = @(
            foreach ($Entry in @($Blocklist.blockedEndpoints)) {
                if (-not $Entry.pattern) { continue }
                [pscustomobject]@{
                    id     = $Entry.id
                    reason = $Entry.reason
                    Regex  = [regex]::new($Entry.pattern, $RegexOptions, $MatchTimeout)
                }
            }
        )
        if ($Entries.Count -eq 0) {
            throw "Graph endpoint blocklist at $BlocklistPath has no patterns"
        }
        $script:CippGraphEndpointBlocklist = $Entries
    }

    foreach ($Candidate in $Candidates) {
        foreach ($Entry in $script:CippGraphEndpointBlocklist) {
            $Reason = $Entry.reason
            try {
                $IsBlocked = $Entry.Regex.IsMatch($Candidate)
            } catch {
                # Match timeout on pathological input: fail closed.
                $IsBlocked = $true
                $Reason = 'path could not be checked in time'
            }
            if ($IsBlocked) {
                $Message = 'Graph endpoint blocked ({0}): {1}' -f $Entry.id, $Reason
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

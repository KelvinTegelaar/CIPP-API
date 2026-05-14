function Invoke-ListContainerLogs {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Action = $Request.Query.Action ?? 'ReadLog'

    # ── Helper: parse raw log lines into structured objects ──
    function ConvertTo-LogEntry {
        param([string[]]$Lines)
        foreach ($Line in $Lines) {
            if ([string]::IsNullOrWhiteSpace($Line)) { continue }
            if ($Line.Length -gt 0 -and [char]::IsWhiteSpace($Line[0])) { continue }
            # ISO 8601: "2026-05-13T10:30:00.000Z [INF] message"
            if ($Line -match '^\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\s+\[(\w+)\]\s+(.*)$') {
                [PSCustomObject]@{
                    Timestamp = $Matches[1]
                    Level     = $Matches[2]
                    Message   = $Matches[3]
                    Raw       = $Line
                }
            # Legacy: "2026-05-13 10:30:00.000 [INF] message"
            } elseif ($Line -match '^\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})\s+\[(\w+)\]\s+(.*)$') {
                [PSCustomObject]@{
                    Timestamp = "$($Matches[1].Replace(' ', 'T'))Z"
                    Level     = $Matches[2]
                    Message   = $Matches[3]
                    Raw       = $Line
                }
            } else {
                [PSCustomObject]@{
                    Timestamp = ''
                    Level     = ''
                    Message   = $Line
                    Raw       = $Line
                }
            }
        }
    }

    # ── Helper: parse a KQL-subset query into LogBridge parameters ──
    # Supported syntax:
    #   where Level == "ERR"
    #   where Level in ("ERR", "CRT", "WRN")
    #   where Message contains "timeout"
    #   where Message !contains "heartbeat"
    #   where Message matches regex "error|fail"
    #   where Timestamp > ago(1h)
    #   where Timestamp > ago(30m)
    #   where Timestamp > ago(2d)
    #   where Timestamp between (ago(2h) .. ago(1h))
    #   where Timestamp > datetime(2026-05-14 10:00)
    #   take 500
    #   sort by Timestamp desc
    #   sort by Timestamp asc
    function ConvertFrom-LogQuery {
        param([string]$Query)

        $params = @{
            Tail           = 500
            Level          = $null
            Search         = $null
            Exclude        = $null
            RegexPattern   = $null
            From           = $null
            To             = $null
            File           = $null
            SearchAll      = $false
            SortNewest     = $true
        }

        # Split on pipe, trim each clause
        $clauses = $Query -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

        foreach ($clause in $clauses) {
            # take N
            if ($clause -match '^\s*take\s+(\d+)\s*$') {
                $params.Tail = [int]$Matches[1]
                continue
            }

            # sort by Timestamp asc/desc
            if ($clause -match '^\s*sort\s+by\s+\w+\s+(asc|desc)\s*$') {
                $params.SortNewest = ($Matches[1] -eq 'desc')
                continue
            }

            # search all files
            if ($clause -match '^\s*search\s+all(\s+files)?\s*$') {
                $params.SearchAll = $true
                continue
            }

            # where clauses
            if ($clause -match '^\s*where\s+(.+)$') {
                $condition = $Matches[1].Trim()

                # Level == "X"
                if ($condition -match '^Level\s*==\s*"(\w+)"\s*$') {
                    $params.Level = $Matches[1]
                }
                # Level in ("X", "Y", ...)
                elseif ($condition -match '^Level\s+in\s*\(\s*(.+)\s*\)\s*$') {
                    $items = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"', "'", ' ') } | Where-Object { $_ }
                    $params.Level = $items -join ','
                }
                # Level != "X"
                elseif ($condition -match '^Level\s*!=\s*"(\w+)"\s*$') {
                    # Exclude this level by including all others
                    $allLevels = @('TRC', 'DBG', 'INF', 'WRN', 'ERR', 'CRT')
                    $excluded = $Matches[1].ToUpper()
                    $params.Level = ($allLevels | Where-Object { $_ -ne $excluded }) -join ','
                }
                # Message contains "text"
                elseif ($condition -match '^Message\s+contains\s+"(.+)"\s*$') {
                    $params.Search = $Matches[1]
                }
                # Message !contains "text"
                elseif ($condition -match '^Message\s+!contains\s+"(.+)"\s*$') {
                    $params.Exclude = $Matches[1]
                }
                # Message matches regex "pattern"
                elseif ($condition -match '^Message\s+matches\s+regex\s+"(.+)"\s*$') {
                    $params.RegexPattern = $Matches[1]
                }
                # Timestamp > ago(Xh/m/d/s)
                elseif ($condition -match '^Timestamp\s*>\s*ago\((\d+)([smhdw])\)\s*$') {
                    $amount = [int]$Matches[1]
                    $unit = $Matches[2]
                    $params.From = switch ($unit) {
                        's' { [DateTime]::UtcNow.AddSeconds(-$amount) }
                        'm' { [DateTime]::UtcNow.AddMinutes(-$amount) }
                        'h' { [DateTime]::UtcNow.AddHours(-$amount) }
                        'd' { [DateTime]::UtcNow.AddDays(-$amount) }
                        'w' { [DateTime]::UtcNow.AddDays(-$amount * 7) }
                    }
                }
                # Timestamp between (ago(Xh) .. ago(Yh))
                elseif ($condition -match '^Timestamp\s+between\s*\(\s*ago\((\d+)([smhdw])\)\s*\.\.\s*ago\((\d+)([smhdw])\)\s*\)\s*$') {
                    $fromAmount = [int]$Matches[1]; $fromUnit = $Matches[2]
                    $toAmount = [int]$Matches[3]; $toUnit = $Matches[4]
                    $params.From = switch ($fromUnit) {
                        's' { [DateTime]::UtcNow.AddSeconds(-$fromAmount) }
                        'm' { [DateTime]::UtcNow.AddMinutes(-$fromAmount) }
                        'h' { [DateTime]::UtcNow.AddHours(-$fromAmount) }
                        'd' { [DateTime]::UtcNow.AddDays(-$fromAmount) }
                        'w' { [DateTime]::UtcNow.AddDays(-$fromAmount * 7) }
                    }
                    $params.To = switch ($toUnit) {
                        's' { [DateTime]::UtcNow.AddSeconds(-$toAmount) }
                        'm' { [DateTime]::UtcNow.AddMinutes(-$toAmount) }
                        'h' { [DateTime]::UtcNow.AddHours(-$toAmount) }
                        'd' { [DateTime]::UtcNow.AddDays(-$toAmount) }
                        'w' { [DateTime]::UtcNow.AddDays(-$toAmount * 7) }
                    }
                }
                # Timestamp between (ago(Xh) .. now())
                elseif ($condition -match '^Timestamp\s+between\s*\(\s*ago\((\d+)([smhdw])\)\s*\.\.\s*now\(\)\s*\)\s*$') {
                    $amount = [int]$Matches[1]; $unit = $Matches[2]
                    $params.From = switch ($unit) {
                        's' { [DateTime]::UtcNow.AddSeconds(-$amount) }
                        'm' { [DateTime]::UtcNow.AddMinutes(-$amount) }
                        'h' { [DateTime]::UtcNow.AddHours(-$amount) }
                        'd' { [DateTime]::UtcNow.AddDays(-$amount) }
                        'w' { [DateTime]::UtcNow.AddDays(-$amount * 7) }
                    }
                }
                # Timestamp > datetime(2026-05-14) or datetime(2026-05-14 10:00)
                elseif ($condition -match '^Timestamp\s*>\s*datetime\((.+)\)\s*$') {
                    $params.From = [DateTime]::Parse($Matches[1]).ToUniversalTime()
                }
                # Timestamp < datetime(...)
                elseif ($condition -match '^Timestamp\s*<\s*datetime\((.+)\)\s*$') {
                    $params.To = [DateTime]::Parse($Matches[1]).ToUniversalTime()
                }
                # Unrecognized where clause — ignore
            }
            # Unrecognized clause — ignore
        }

        return $params
    }

    try {
        switch ($Action) {
            'ListFiles' {
                $Results = [Craft.Services.LogBridge]::GetLogFiles()
                $Body = @{ Results = @($Results) }
            }
            'ReadLog' {
                $Tail = [int]($Request.Query.Tail ?? '500')
                $Level = $Request.Query.Level
                $Search = $Request.Query.Search
                $File = $Request.Query.File
                $Exclude = $Request.Query.Exclude
                $Regex = $Request.Query.Regex
                $SortDesc = $Request.Query.SortDesc

                $From = $null
                $To = $null
                if ($Request.Query.From) { $From = [DateTime]::Parse($Request.Query.From).ToUniversalTime() }
                if ($Request.Query.To) { $To = [DateTime]::Parse($Request.Query.To).ToUniversalTime() }

                $LevelParam = if ([string]::IsNullOrEmpty($Level)) { $null } else { $Level }
                $SearchParam = if ([string]::IsNullOrEmpty($Search)) { $null } else { $Search }
                $FileParam = if ([string]::IsNullOrEmpty($File)) { $null } else { $File }
                $ExcludeParam = if ([string]::IsNullOrEmpty($Exclude)) { $null } else { $Exclude }
                $RegexParam = if ([string]::IsNullOrEmpty($Regex)) { $null } else { $Regex }
                $SortNewest = $SortDesc -eq 'true'

                $Lines = [Craft.Services.LogBridge]::ReadLog($Tail, $LevelParam, $SearchParam, $FileParam, $From, $To, $ExcludeParam, $RegexParam, $SortNewest)
                $Results = ConvertTo-LogEntry -Lines $Lines
                $Body = @{ Results = @($Results) }
            }
            'SearchAll' {
                $Search = $Request.Query.Search
                $Level = $Request.Query.Level
                $Tail = [int]($Request.Query.Tail ?? '500')
                $Exclude = $Request.Query.Exclude
                $Regex = $Request.Query.Regex
                $SortDesc = $Request.Query.SortDesc

                $From = $null
                $To = $null
                if ($Request.Query.From) { $From = [DateTime]::Parse($Request.Query.From).ToUniversalTime() }
                if ($Request.Query.To) { $To = [DateTime]::Parse($Request.Query.To).ToUniversalTime() }

                $SearchParam = if ([string]::IsNullOrEmpty($Search)) { $null } else { $Search }
                $LevelParam = if ([string]::IsNullOrEmpty($Level)) { $null } else { $Level }
                $ExcludeParam = if ([string]::IsNullOrEmpty($Exclude)) { $null } else { $Exclude }
                $RegexParam = if ([string]::IsNullOrEmpty($Regex)) { $null } else { $Regex }
                $SortNewest = $SortDesc -eq 'true'

                $Lines = [Craft.Services.LogBridge]::SearchAllFiles($SearchParam, $LevelParam, $From, $To, $Tail, $ExcludeParam, $RegexParam, $SortNewest)
                $Results = ConvertTo-LogEntry -Lines $Lines
                $Body = @{ Results = @($Results) }
            }
            'Query' {
                $Query = $Request.Query.Query ?? $Request.Body.Query
                if ([string]::IsNullOrWhiteSpace($Query)) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = 'Query parameter is required' }
                    }
                }

                $p = ConvertFrom-LogQuery -Query $Query

                $LevelParam = if ([string]::IsNullOrEmpty($p.Level)) { $null } else { $p.Level }
                $SearchParam = if ([string]::IsNullOrEmpty($p.Search)) { $null } else { $p.Search }
                $ExcludeParam = if ([string]::IsNullOrEmpty($p.Exclude)) { $null } else { $p.Exclude }
                $RegexParam = if ([string]::IsNullOrEmpty($p.RegexPattern)) { $null } else { $p.RegexPattern }
                $FileParam = if ([string]::IsNullOrEmpty($p.File)) { $null } else { $p.File }

                if ($p.SearchAll) {
                    $Lines = [Craft.Services.LogBridge]::SearchAllFiles($SearchParam, $LevelParam, $p.From, $p.To, $p.Tail, $ExcludeParam, $RegexParam, $p.SortNewest)
                } else {
                    $Lines = [Craft.Services.LogBridge]::ReadLog($p.Tail, $LevelParam, $SearchParam, $FileParam, $p.From, $p.To, $ExcludeParam, $RegexParam, $p.SortNewest)
                }

                $Results = ConvertTo-LogEntry -Lines $Lines
                $Body = @{ Results = @($Results) }
            }
            'GetInfo' {
                $Body = @{
                    Results = @{
                        CurrentFile  = [Craft.Services.LogBridge]::GetCurrentLogPath()
                        LogDirectory = [Craft.Services.LogBridge]::GetLogDirectory()
                        Files        = @([Craft.Services.LogBridge]::GetLogFiles())
                    }
                }
            }
            default {
                $Body = @{ Results = "Unknown action: $Action" }
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = $Body
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Container logs error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}

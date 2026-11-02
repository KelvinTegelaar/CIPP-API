function Get-CippReportTableData {
    <#
    .SYNOPSIS
        Build flat table rows for a pre-built report table whose data lives in a nested shape a generic
        single-collection dataSource cannot read.
    .DESCRIPTION
        Some report tables need data that is not one flat row per record - for example the Secure Score
        controls, which live in a nested controlScores array inside a handful of daily snapshot rows. A
        preset here reads the raw collection rows and returns an ordered list of flat rows (hashtables),
        each key a field a table column can name. The report resolver feeds these rows through the same
        column mapping every hand-built table uses, so the columns read their fields exactly as normal.

        Presets:
          secureScoreFailing <- SecureScore  the latest snapshot's controls that are not fully achieved
                                              (scoreInPercentage < 100), worst first.
    .PARAMETER Preset
        Which table to build.
    .PARAMETER Rows
        The raw collection rows for that table's source.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Preset,
        [AllowEmptyCollection()][object[]]$Rows = @()
    )

    $AsDouble = { param($Value) $n = "$Value" -as [double]; if ($null -ne $n) { $n } else { $null } }
    $Pct = { param($Value) $n = & $AsDouble $Value; if ($null -eq $n) { '' } elseif ([math]::Round($n) -eq $n) { "$([int]$n)%" } else { "$([math]::Round($n, 1))%" } }
    # Some control statuses arrive as HTML (implementationStatus); flatten to a short line of plain text.
    $Plain = {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
        $Clean = [regex]::Replace($Text, '<[^>]+>', ' ')
        $Clean = [System.Net.WebUtility]::HtmlDecode($Clean)
        $Clean = [regex]::Replace($Clean, '\s+', ' ').Trim()
        if ($Clean.Length -gt 160) { $Clean = $Clean.Substring(0, 159).TrimEnd() + [char]0x2026 }
        $Clean
    }

    switch ($Preset) {
        'secureScoreFailing' {
            # SecureScore is a series of daily snapshots; take the most recent one and read its per-control
            # scores. A control that is not fully achieved (below 100%) is one worth listing.
            if (@($Rows).Count -eq 0) { return @() }
            $Latest = @($Rows | Sort-Object -Property @{ Expression = { [datetime]("$($_.createdDateTime)" -as [datetime]) } } -Descending | Select-Object -First 1)
            if (-not $Latest) { $Latest = @($Rows)[-1] }
            $Controls = @($Latest.controlScores)
            if (@($Controls).Count -eq 0) { return @() }
            $Failing = @($Controls | Where-Object {
                    $p = & $AsDouble $_.scoreInPercentage
                    $null -ne $p -and $p -lt 100
                })
            $Ordered = @($Failing | Sort-Object -Property @{ Expression = { [double](& $AsDouble $_.scoreInPercentage) } }, @{ Expression = { "$($_.controlName)" } })
            return @($Ordered | ForEach-Object {
                    [ordered]@{
                        control  = "$($_.controlName)"
                        category = "$($_.controlCategory)"
                        status   = $(if ($_.implementationStatus) { (& $Plain "$($_.implementationStatus)") } else { "$($_.on)" })
                        percent  = (& $Pct $_.scoreInPercentage)
                    }
                })
        }
        default {
            throw "Unknown report table preset '$Preset'."
        }
    }
}

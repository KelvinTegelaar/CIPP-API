function Get-CIPPBaselineMinimumOSTarget {
    <#
    .SYNOPSIS
        Works out the minimum OS version a platform's Intune policies should require, from an
        endoflife.date release list.
    .DESCRIPTION
        Scope picks the releases that stay allowed: 'supported' (every maintained release), 'latestTwo'
        or 'latest'. The answer is the lowest version among them.

        CadenceDays is the grace period. A release that reached end of life stays allowed for that many
        days, and a new update only becomes the minimum once it is that old; until then only the
        release itself is required (18.0 rather than 18.7.12). CadenceDays 0 gives the value with no
        grace, which app protection policies use as their warning version.

        Android has no update numbers, so its patch level is the first of the month, which is when
        Google publishes each security bulletin. Windows LTSC and IoT releases are ignored: their long
        support would otherwise keep builds allowed that Pro and Enterprise no longer patch.

        Returns Version and, for Android, PatchLevel (yyyy-MM-dd). Returns nothing when no release
        qualifies.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android')]
        [string]$Platform,
        $Releases,
        [ValidateSet('supported', 'latestTwo', 'latest')]
        [string]$Scope = 'supported',
        [int]$CadenceDays = 14,
        [datetime]$Now = [datetime]::UtcNow
    )

    $ToDate = { param($Value) if ($Value) { [datetime]::Parse("$Value", [cultureinfo]::InvariantCulture) } }
    $GraceStart = $Now.AddDays(-$CadenceDays)

    $Candidates = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Release in @($Releases | Sort-Object -Property { & $ToDate $_.releaseDate } -Descending)) {
        if ($Release.isLts -eq $true -or "$($Release.name)" -match 'lts|iot') { continue }
        $Released = & $ToDate $Release.releaseDate
        if (-not $Released -or $Released -gt $Now) { continue }
        $EndOfLife = & $ToDate $Release.eolFrom
        # The end of life date decides when there is one: endoflife.date keeps a release "maintained"
        # through paid extended support (Windows 10 ESU), which does not make it supported here.
        $Supported = if ($EndOfLife) { $EndOfLife -gt $GraceStart } else { $Release.isMaintained -eq $true }
        if (-not $Supported) { continue }

        $Name = "$($Release.name)"
        $Text = switch ($Platform) {
            'Windows' { "$($Release.latestVersion)" }
            'Android' { $Name }
            default {
                $UpdateDate = & $ToDate $Release.latestDate
                if ($Release.latestVersion -and $UpdateDate -and $UpdateDate -le $GraceStart) { "$($Release.latestVersion)" }
                elseif ($Name -match '\.') { $Name }
                else { "$Name.0" }
            }
        }
        $Version = ConvertTo-CIPPBaselineOSVersion -Text $Text
        # Windows lists one row per edition, so the same build shows up several times.
        if (-not $Version -or -not $Seen.Add("$Version")) { continue }
        $Candidates.Add([PSCustomObject]@{ Text = $Text; Version = $Version })
    }
    if ($Candidates.Count -eq 0) { return }

    $Take = switch ($Scope) { 'latest' { 1 } 'latestTwo' { 2 } default { $Candidates.Count } }
    $Lowest = @($Candidates | Select-Object -First $Take | Sort-Object -Property Version)[0]

    $Target = [PSCustomObject]@{
        Version    = if ($Platform -eq 'Windows') { "$($Lowest.Version)" } else { $Lowest.Text }
        PatchLevel = $null
    }
    if ($Platform -eq 'Android') {
        $Bulletin = [datetime]::new($Now.Year, $Now.Month, 1)
        while ($Bulletin -gt $GraceStart) { $Bulletin = $Bulletin.AddMonths(-1) }
        $Target.PatchLevel = $Bulletin.ToString('yyyy-MM-dd')
    }
    $Target
}

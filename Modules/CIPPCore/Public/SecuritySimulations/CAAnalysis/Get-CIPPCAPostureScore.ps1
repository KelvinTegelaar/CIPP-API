function Get-CIPPCAPostureScore {
    <#
    .SYNOPSIS
        Computes the Conditional Access score on a 1-10 scale.
    .DESCRIPTION
        The score is the share of applicable persona-matrix controls that an enforced policy covers
        (report-only counting half), on a 10-point scale, nudged down by the serious policy findings: half a
        point per Critical and a quarter per High, capped at two points in total.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Findings,
        [Parameter(Mandatory = $true)]
        $PersonaMatrix
    )

    $Round = { param($Value) [int][math]::Round([double]$Value, [System.MidpointRounding]::AwayFromZero) }

    $Applicable = @($PersonaMatrix.cells | Where-Object { $_.state -notin @('NotApplicable', 'Unlicensed') })
    $Covered = 0.0
    foreach ($Cell in $Applicable) {
        if ($Cell.state -eq 'Enforced') { $Covered += 1 }
        elseif ($Cell.state -eq 'ReportOnly') { $Covered += 0.5 }
    }
    $Coverage = if ($Applicable.Count -gt 0) { ($Covered / $Applicable.Count) * 10 } else { 10 }

    $Serious = @($Findings | Where-Object { "$($_.category)" -ne 'Persona coverage' })
    $Critical = @($Serious | Where-Object { "$($_.severity)" -eq 'Critical' }).Count
    $High = @($Serious | Where-Object { "$($_.severity)" -eq 'High' }).Count
    $Penalty = [math]::Min(2, ($Critical * 0.5) + ($High * 0.25))

    $Score = [math]::Max(1, [math]::Min(10, (& $Round ($Coverage - $Penalty))))

    [PSCustomObject]@{
        score            = [int]$Score
        scoreMax         = 10
        enforcedControls = [int](& $Round $Covered)
        applicableControls = $Applicable.Count
        criticalFindings = $Critical
        highFindings     = $High
    }
}

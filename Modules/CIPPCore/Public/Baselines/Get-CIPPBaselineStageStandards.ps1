function Get-CIPPBaselineStageStandards {
    <#
    .SYNOPSIS
        Returns the standard instance keys each stage of a baseline rolls out.
    .DESCRIPTION
        Emits one string array per stage, in stage order, so callers take the first N for a
        tenant at stage N. Package standards expand to their member instance keys, which are
        the keys resolved BaselineAlignment rows carry.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Baseline,
        $Definitions
    )

    foreach ($StageDef in @($Baseline.stages)) {
        $Keys = foreach ($Config in @($StageDef.standardsConfig)) {
            if (-not $Config) { continue }
            $Definition = $Definitions | Where-Object { $_.name -eq "$($Config.standard)" } | Select-Object -First 1
            if ($Definition.package) {
                (Expand-CIPPBaselineTemplatePackage -Definition $Definition -Config $Config).instance
            } else {
                "$($Config.instance ?? $Config.standard)"
            }
        }
        Write-Output -NoEnumerate ([string[]]@($Keys | Where-Object { $_ }))
    }
}

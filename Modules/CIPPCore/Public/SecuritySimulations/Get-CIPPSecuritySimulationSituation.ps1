function Get-CIPPSecuritySimulationSituation {
    <#
    .SYNOPSIS
        Returns the predefined Conditional Access sign-in situations.
    .DESCRIPTION
        Config/SecuritySimulations/CASituations.json holds one entry per predefined sign-in (persona,
        sign-in conditions, expected outcome, the control that is missing when the outcome is not met).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Path = Join-Path $env:CIPPRootPath 'Config/SecuritySimulations/CASituations.json'
    if (-not (Test-Path $Path)) { return @() }
    try {
        @([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop | Where-Object { $_.id })
    } catch {
        Write-Information "Get-CIPPSecuritySimulationSituation: failed to parse CASituations.json: $($_.Exception.Message)"
        @()
    }
}

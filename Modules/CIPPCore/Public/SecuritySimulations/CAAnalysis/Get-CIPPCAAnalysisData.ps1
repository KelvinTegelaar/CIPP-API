function Get-CIPPCAAnalysisData {
    <#
    .SYNOPSIS
        Loads one static reference dataset used by the Conditional Access gap analysis.
    .DESCRIPTION
        Reads Config/SecuritySimulations/CAAnalysis/<Name>.json under the CIPP root and returns the parsed
        object.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Path = Join-Path $env:CIPPRootPath "Config/SecuritySimulations/CAAnalysis/$Name.json"
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Information "Get-CIPPCAAnalysisData: dataset '$Name' was not found at $Path"
        return $null
    }

    try {
        [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -Depth 20 -ErrorAction Stop
    } catch {
        Write-Information "Get-CIPPCAAnalysisData: failed to parse $Name.json: $($_.Exception.Message)"
        $null
    }
}

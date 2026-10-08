function Initialize-CippTestSuiteSecuritySimulations {
    <#
    .SYNOPSIS
        Builds one Security Simulation context for the whole suite before Invoke-CIPPTestCollection runs it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Tenant)

    $script:CippSecuritySimulationContext = $null
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Context = Get-CippSecuritySimulationContext -Tenant $Tenant
    $script:CippSecuritySimulationContext = $Context

    $Slowest = @($Context.Timings | Sort-Object -Property Seconds -Descending | Select-Object -First 5 | ForEach-Object { '{0} {1:N1}s' -f $_.Name, $_.Seconds }) -join ', '
    Write-Information ('  [SecuritySimulations] Setup {0:N1}s: {1} What If, {2} standards (slowest {3})' -f $Stopwatch.Elapsed.TotalSeconds, $Context.WhatIf.Count, $Context.Standards.Count, $Slowest)
}

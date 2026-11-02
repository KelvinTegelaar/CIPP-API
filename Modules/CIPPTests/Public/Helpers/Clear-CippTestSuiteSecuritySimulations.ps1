function Clear-CippTestSuiteSecuritySimulations {
    <#
    .SYNOPSIS
        Drops the shared Security Simulation context once Invoke-CIPPTestCollection has run the suite.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $script:CippSecuritySimulationContext = $null
}

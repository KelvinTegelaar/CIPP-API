function Invoke-CippTestSecuritySimulation_StolenTokenReplay {
    <#
    .SYNOPSIS
    Security Simulation - Stolen session token replay

    .DESCRIPTION
    An attacker replays a session token stolen through a fake sign-in page and signs in as the user without re-entering a password or MFA.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'StolenTokenReplay'
}
function Invoke-CippTestSecuritySimulation_GuestReshareSprawl {
    <#
    .SYNOPSIS
    Security Simulation - Guest re-share sprawl

    .DESCRIPTION
    A guest re-shares files they were given, spreading access to more outsiders than the owner intended.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'GuestReshareSprawl'
}
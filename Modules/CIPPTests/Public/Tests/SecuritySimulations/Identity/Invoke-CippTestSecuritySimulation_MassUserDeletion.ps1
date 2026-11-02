function Invoke-CippTestSecuritySimulation_MassUserDeletion {
    <#
    .SYNOPSIS
    Security Simulation - Mass user deletion

    .DESCRIPTION
    A compromised administrator deletes many user accounts at once to disrupt the business.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'MassUserDeletion'
}
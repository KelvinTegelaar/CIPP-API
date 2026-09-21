function Invoke-CippTestSecuritySimulation_MassGroupDeletion {
    <#
    .SYNOPSIS
    Security Simulation - Mass group deletion

    .DESCRIPTION
    A compromised administrator deletes many groups, breaking access, mail flow and team membership across the tenant.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'MassGroupDeletion'
}
function Invoke-CippTestSecuritySimulation_RoleAssignmentEscalation {
    <#
    .SYNOPSIS
    Security Simulation - Privilege escalation by role assignment

    .DESCRIPTION
    An attacker who took over an account with role-management rights grants itself higher privileges and plants a back-door application.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'RoleAssignmentEscalation'
}
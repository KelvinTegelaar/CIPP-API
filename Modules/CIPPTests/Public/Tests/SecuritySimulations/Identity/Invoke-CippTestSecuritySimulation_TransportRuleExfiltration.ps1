function Invoke-CippTestSecuritySimulation_TransportRuleExfiltration {
    <#
    .SYNOPSIS
    Security Simulation - Transport-rule exfiltration

    .DESCRIPTION
    An attacker with Exchange admin rights creates an organization-wide transport rule that blind-copies mail to an outside address.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'TransportRuleExfiltration'
}
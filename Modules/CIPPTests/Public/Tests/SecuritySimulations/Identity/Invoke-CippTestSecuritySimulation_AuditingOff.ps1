function Invoke-CippTestSecuritySimulation_AuditingOff {
    <#
    .SYNOPSIS
    Security Simulation - Silent tenant: auditing turned off

    .DESCRIPTION
    With the Unified Audit Log disabled, an attacker acts inside the tenant knowing that key actions leave no usable trail.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'AuditingOff'
}
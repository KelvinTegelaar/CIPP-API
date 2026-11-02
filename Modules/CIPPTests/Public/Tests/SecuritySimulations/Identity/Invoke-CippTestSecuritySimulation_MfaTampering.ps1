function Invoke-CippTestSecuritySimulation_MfaTampering {
    <#
    .SYNOPSIS
    Security Simulation - MFA tampering after compromise

    .DESCRIPTION
    After taking over a privileged account, an attacker strips users' MFA and revokes their sessions to lock in control.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'MfaTampering'
}
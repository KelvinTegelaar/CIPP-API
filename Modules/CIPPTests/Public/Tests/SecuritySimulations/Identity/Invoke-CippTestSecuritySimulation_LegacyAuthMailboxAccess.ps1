function Invoke-CippTestSecuritySimulation_LegacyAuthMailboxAccess {
    <#
    .SYNOPSIS
    Security Simulation - Legacy authentication mailbox access

    .DESCRIPTION
    An attacker uses an older mail protocol that cannot prompt for MFA to reach a mailbox with a stolen password.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'LegacyAuthMailboxAccess'
}
function Invoke-CippTestSecuritySimulation_MailboxRuleExfiltration {
    <#
    .SYNOPSIS
    Security Simulation - Mailbox rule exfiltration

    .DESCRIPTION
    An attacker with mailbox access sets up inbox rules and forwarding to copy mail out of the tenant automatically.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'MailboxRuleExfiltration'
}
function Invoke-CippTestSecuritySimulation_MailboxPermissionGrab {
    <#
    .SYNOPSIS
    Security Simulation - Mailbox permission grab

    .DESCRIPTION
    An attacker with admin rights grants itself full access to other users' mailboxes and reads them directly.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'MailboxPermissionGrab'
}
function Invoke-CippTestSecuritySimulation_AdminNonCompliantDevice {
    <#
    .SYNOPSIS
    Security Simulation - Global Admin on a non-compliant device

    .DESCRIPTION
    A Global Administrator signs in from an unmanaged, non-compliant computer, giving an attacker on that machine full control of the tenant.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'AdminNonCompliantDevice'
}
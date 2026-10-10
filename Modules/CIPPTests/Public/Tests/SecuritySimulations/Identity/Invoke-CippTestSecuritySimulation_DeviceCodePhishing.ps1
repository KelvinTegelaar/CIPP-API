function Invoke-CippTestSecuritySimulation_DeviceCodePhishing {
    <#
    .SYNOPSIS
    Security Simulation - Device-code phishing

    .DESCRIPTION
    An attacker tricks a user into approving a device-code sign-in and receives a fully authenticated token that already includes the MFA claim.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'DeviceCodePhishing'
}